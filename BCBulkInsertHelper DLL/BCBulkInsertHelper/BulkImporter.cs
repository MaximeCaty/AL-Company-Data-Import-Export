using System.Collections.Generic;
using System.Linq;
using System;
using System.Data;
using Microsoft.Data.SqlClient;
using System.IO.Compression;

namespace BCBulkInsertHelper
{
    
    static class OpenedSqlConnection
    {
        public static SqlConnection Connection;
        public static String ConnectionString;
        public static SqlDataReader DataReader;
    }

    public class SqlCommandHelper
    {
        public SqlDataReader ExecuteReader(String SQLConnectionString, string SQLQueryString, int CommandBehavior)
        {
            if (OpenedSqlConnection.ConnectionString == null || SQLConnectionString != OpenedSqlConnection.ConnectionString)
            {
                OpenedSqlConnection.ConnectionString = SQLConnectionString;
                OpenedSqlConnection.Connection = new SqlConnection(SQLConnectionString);
                OpenedSqlConnection.Connection.Open();
            } else {
                // Clsoe previous reader if any
                if (OpenedSqlConnection.DataReader != null)
                {
                    if (OpenedSqlConnection.DataReader.IsClosed == false) { OpenedSqlConnection.DataReader.Close(); }
                }
            }
            SqlCommand SqlCommand = new SqlCommand(SQLQueryString, OpenedSqlConnection.Connection);
            OpenedSqlConnection.DataReader = SqlCommand.ExecuteReader((CommandBehavior)CommandBehavior);
            return OpenedSqlConnection.DataReader;
        }
    }
    public class BulkImporterExt
    {
        private readonly DataTable _dataTable = new DataTable();
        private readonly List<string> _pkColumns = new List<string>();
        private DataRow _currentRow;
        private readonly DateTime ALBlankDateTime = new DateTime(1753, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        public void AddColumn(string columnName, string typeName, bool isPK = false)
        {
            if (_dataTable.Columns.Contains(columnName))
                return;

            Type type = GetTypeFromName(typeName.ToLowerInvariant());

            _dataTable.Columns.Add(columnName, type);

            if (isPK)
                _pkColumns.Add(columnName);
        }

        private Type GetTypeFromName(string typeName)
        {
            switch (typeName.ToLowerInvariant())
            {
                case "string":
                case "text":
                case "code":
                    return typeof(string);
                    break;
                case "int32":
                case "integer":
                case "int":
                    return typeof(int);
                    break;
                case "duration":
                case "timespan":
                case "int64":
                case "biginteger":
                    return typeof(long);
                    break;
                case "decimal":
                    return typeof(decimal);
                    break;

                case "datetime":
                case "date":
                case "time":
                    return typeof(DateTime);
                    break;
                case "boolean":
                case "bool":
                    return typeof(bool);
                    break;
                case "guid":
                    return typeof(Guid);
                    break;
                case "blob":
                case "binary":
                case "varbinary":
                case "media":
                case "image":
                    return typeof(byte[]);
                    break;

                default:
                    return typeof(object);
                    break;
            }
        }

        /// <summary>
        /// Marks a column as always empty for the current chunk : NewRow() then pre-fills it with the BC empty
        /// value of its type, so the caller never has to push a value for it row by row.
        /// Must be called after AddColumn and before the first BeginRow() that actually feeds a row :
        /// DefaultValue is applied when the DataRow is created, not retroactively.
        /// typeName uses the same names as AddColumn.
        /// </summary>
        public void SetColumnEmptyDefault(int columnIndex, string typeName)
        {
            if (columnIndex < 0 || columnIndex >= _dataTable.Columns.Count)
                return;

            _dataTable.Columns[columnIndex].DefaultValue = GetEmptyValueFromName(typeName.ToLowerInvariant());
        }

        private object GetEmptyValueFromName(string typeName)
        {
            switch (typeName)
            {
                case "string":
                case "text":
                case "code":
                    return "";
                case "int32":
                case "integer":
                case "int":
                    return 0;
                case "duration":
                case "timespan":
                case "int64":
                case "biginteger":
                    return 0L;
                case "decimal":
                    return 0m;
                case "datetime":
                case "date":
                case "time":
                    // BC stores an empty date/time/datetime as 1753-01-01, not DateTime.MinValue
                    return ALBlankDateTime;
                case "boolean":
                case "bool":
                    return false;
                case "guid":
                    return Guid.Empty;
                case "blob":
                case "binary":
                case "media":
                case "image":
                    return new byte[0];
                case "varbinary":
                    // Empty BC RecordID : table no as int32 zero + 00 00 terminator = 6 zero bytes
                    return new byte[6];
                default:
                    return DBNull.Value;
            }
        }

        public void BeginRow()
        {
            _currentRow = _dataTable.NewRow();
        }

        public void AddRowValueALTime(DateTime value, int columnIndex)
        {
            if (value == DateTime.MinValue || value == null) // this catches 0DT from AL
            {
                _currentRow[columnIndex] = ALBlankDateTime;
            }
            else
            {
                _currentRow[columnIndex] = new DateTime(1753, 1, 1, value.Hour, value.Minute, value.Second, value.Millisecond, DateTimeKind.Utc);
            }
        }

        public void AddRowValueALDate(int Year, int Month, int Day, int columnIndex, bool isClosing = false)
        {
            if (Year <= 1753) // this catches 0DT from AL
            {
                _currentRow[columnIndex] = ALBlankDateTime;
            }
            else if (isClosing)
            {
                // BC flags a closing date in SQL with time 23:59:59.000 (normal date = 00:00:00.000)
                _currentRow[columnIndex] = new DateTime(Year, Month, Day, 23, 59, 59, DateTimeKind.Utc);
            }
            else
            {
                _currentRow[columnIndex] = new DateTime(Year, Month, Day, 0, 0, 0, DateTimeKind.Utc);
            }
        }
        
        public void AddRowValue(DateTime value, int columnIndex)
        {
            if (value == DateTime.MinValue || value == null) // catch 0DT
            {
                _currentRow[columnIndex] = ALBlankDateTime;
            }
            else if (value.Kind == DateTimeKind.Unspecified)
            {
                // Most common case from AL: treat as local → convert to UTC
                _currentRow[columnIndex] = DateTime.SpecifyKind(value, DateTimeKind.Local).ToUniversalTime();
            }
            else if (value.Kind == DateTimeKind.Local)
            {
                _currentRow[columnIndex] = value.ToUniversalTime();
            }
            else // Already Utc (not from AL)
            {
                _currentRow[columnIndex] = value;
            }
        }

        public void AddRowValueBlob(Byte[] value, int ColumnIndex)
        {
            // Business Central compress blob using Delfate
            _currentRow[ColumnIndex] = CompressForBusinessCentral(value);
        }

        public void AddRowValue(Byte[] value, int ColumnIndex)
        {
            _currentRow[ColumnIndex] = value;
        }

        public void AddRowValue(object value, int ColumnIndex)
        {
            _currentRow[ColumnIndex] = value;
        }

        public void EndRow()
        {
            _dataTable.Rows.Add(_currentRow);
        }

        public void WriteToServer(string connectionString, string mainTableName, bool useTableLock = true, int batchSize = 10000)
        {
            if (_dataTable.Rows.Count == 0)
                return;

            // TableLock = one BU lock on whole table (fast, single writer). Drop it for per-row locks
            // when several threads bulk-insert the same table concurrently.
            SqlBulkCopyOptions bulkOptions = SqlBulkCopyOptions.KeepIdentity;
            if (useTableLock)
                bulkOptions |= SqlBulkCopyOptions.TableLock;

            // Detect field from table extension (ending with $ + app guid)
            bool hasExtensionFields = false;
            List<string> extensionColumns = new List<string>();

            foreach (DataColumn col in _dataTable.Columns)
            {
                string name = col.ColumnName;
                int dollarPos = name.LastIndexOf('$');
                if (dollarPos > -1 && dollarPos < name.Length - 1)
                {
                    string guidPart = name.Substring(dollarPos + 1);
                    if (Guid.TryParse(guidPart, out _))
                    {
                        hasExtensionFields = true;
                        extensionColumns.Add(name);
                    }
                }
            }

            // 1. Bulk Insert in main base table
            List<string> mainColumns = new List<string>();
            foreach (DataColumn col in _dataTable.Columns)
            {
                if (!extensionColumns.Contains(col.ColumnName, StringComparer.OrdinalIgnoreCase))
                    mainColumns.Add(col.ColumnName);
            }

            if (mainColumns.Count > 0)
            {
                using (var bulk = new SqlBulkCopy(connectionString, bulkOptions))
                {
                    bulk.DestinationTableName = mainTableName;
                    bulk.BatchSize = batchSize;
                    bulk.BulkCopyTimeout = 0;
                    bulk.EnableStreaming = true;

                    foreach (string col in mainColumns)
                        bulk.ColumnMappings.Add(col, col);

                    bool Sucess = true;
                    string errorDetails = ""; 
                    try
                    {
                        bulk.WriteToServer(_dataTable);
                    }
                    catch (Exception ex)
                    {
                        Sucess = false;
                        var mappingsInfo = string.Join(Environment.NewLine,
                                            _pkColumns.Select(c => $"{c,-40} → {c}")
                                            .Concat(extensionColumns.Select(c => $"{c,-40} → {c.Replace('$', '_')}")));
                        errorDetails =
                                $"BulkCopy failed into {mainTableName}{Environment.NewLine}" +
                                $"Error: {ex.Message}" +
                                $"Mappings used:{Environment.NewLine}{mappingsInfo}{Environment.NewLine}";

                                
                    }
                    if (!Sucess) { throw new Exception(errorDetails); }
                }
            }

            // 2. Bulk insert in extension table if needed
            string extTableName = mainTableName + "$ext"; 
            if (!hasExtensionFields)
            {
                hasExtensionFields = TableExists(connectionString, extTableName);
            }
            if (hasExtensionFields && _pkColumns.Count > 0)
            {
                 using (var bulk = new SqlBulkCopy(connectionString, bulkOptions))
                    {
                        bulk.DestinationTableName = extTableName;
                        bulk.BatchSize = batchSize;
                        bulk.BulkCopyTimeout = 0;
                        bulk.EnableStreaming = true;

                        // Add PK
                        foreach (string pk in _pkColumns)
                        {
                            bulk.ColumnMappings.Add(pk, pk);  // source = destination
                        }

                        // Add other fields extensions, with lowercase GUID
                        foreach (string extCol in extensionColumns) // ex: "Field$98860128-1333-4598-A3DA-0590804648B7"
                        {
                            // Search for the $ to force lowercase GUID
                            int dollarIndex = extCol.LastIndexOf('$');
                            if (dollarIndex > -1)
                            {
                                string fieldName = extCol.Substring(0, dollarIndex + 1);
                                string guidPart = extCol.Substring(dollarIndex + 1);
                                string destColumn = fieldName + guidPart.ToLowerInvariant();
                                bulk.ColumnMappings.Add(extCol, destColumn);
                            }
                        }

                        bool Sucess = true;
                        string errorDetails = "";
                        try
                        { 
                            bulk.WriteToServer(_dataTable);
                        }
                        catch (Exception ex)
                        {
                            Sucess = false;
                            var mappingsInfo = string.Join(Environment.NewLine,
                                                _pkColumns.Select(c => $"{c,-40} → {c}")
                                                .Concat(extensionColumns.Select(c => $"{c,-40} → {c.Replace('$', '_')}")));
                            errorDetails =
                                    $"BulkCopy failed into {extTableName}{Environment.NewLine}" +
                                    $"Error: {ex.Message}" +
                                    $"Mappings used:{Environment.NewLine}{mappingsInfo}{Environment.NewLine}";
                    }
                    if (!Sucess) { throw new Exception(errorDetails); }
                }
                
            }
            _dataTable.Clear();
        }

        /// <summary>
        /// Disables the secondary (nonclustered) indexes of a table, plus the clustered index of the SIFT indexed
        /// views built on it, so a bulk load does not maintain and log them row by row.
        /// Returns the number of indexes left disabled (table indexes + SIFT views).
        /// Never touches the clustered index (disabling it would make the data unreachable), nor primary keys,
        /// unique constraints or unique indexes (disabling those would silently stop enforcing uniqueness).
        /// Call RebuildDisabledIndexes when the load is finished : until then the table has no secondary indexes,
        /// so anything querying it will be slow.
        /// </summary>
        public int DisableSecondaryIndexes(string connectionString, string tableName)
        {
            const string sql = @"
-- Resolve the object once and fail loudly : QUOTENAME returns NULL above 128 characters, which used to
-- turn this whole batch into a silent no-op (empty command, count 0, no exception).
DECLARE @oid int = OBJECT_ID(QUOTENAME(@table));
IF @oid IS NULL
    THROW 50001, 'DisableSecondaryIndexes : table not found (name too long for QUOTENAME, or not in the current database).', 1;

DECLARE @cmd nvarchar(max) = N'';
SELECT @cmd = @cmd + N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON '
            + QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(i.object_id)) + N' DISABLE;'
FROM sys.indexes i
WHERE i.object_id = @oid
  AND i.type = 2                 -- nonclustered only
  AND i.is_disabled = 0
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND i.is_unique = 0;

-- SIFT indexed views ($VSIFT$) are separate objects maintained synchronously on every insert, and on the
-- ledger tables they cost more than the insert itself. Disabling the clustered index of a VIEW only
-- de-materializes it (unlike on a table, no data is orphaned) : the rebuild below re-materializes it.
SELECT @cmd = @cmd + N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON '
            + QUOTENAME(SCHEMA_NAME(v.schema_id)) + N'.' + QUOTENAME(v.name) + N' DISABLE;'
FROM sys.views v
JOIN sys.indexes i ON i.object_id = v.object_id AND i.type = 1 AND i.is_disabled = 0
WHERE EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
              WHERE d.referencing_id = v.object_id AND d.referenced_id = @oid);

IF @cmd <> N'' EXEC sp_executesql @cmd;

SELECT (SELECT COUNT(*) FROM sys.indexes
        WHERE object_id = @oid AND type = 2 AND is_disabled = 1)
     + (SELECT COUNT(*) FROM sys.views v
        JOIN sys.indexes i ON i.object_id = v.object_id AND i.type = 1 AND i.is_disabled = 1
        WHERE EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
                      WHERE d.referencing_id = v.object_id AND d.referenced_id = @oid));";

            return ExecuteIndexCommand(connectionString, tableName, sql);
        }

        /// <summary>
        /// Rebuilds every disabled nonclustered index of a table and every disabled SIFT view built on it,
        /// which is what re-enables them.
        /// Idempotent : safe to call when nothing is disabled, and safe to call again after a failed run,
        /// because it works from the current is_disabled state rather than a remembered list.
        /// Returns the number of indexes still disabled afterwards (0 when everything was rebuilt).
        /// </summary>
        public int RebuildDisabledIndexes(string connectionString, string tableName)
        {
            const string sql = @"
DECLARE @oid int = OBJECT_ID(QUOTENAME(@table));
IF @oid IS NULL
    THROW 50002, 'RebuildDisabledIndexes : table not found (name too long for QUOTENAME, or not in the current database).', 1;

DECLARE @cmd nvarchar(max) = N'';
SELECT @cmd = @cmd + N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON '
            + QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(i.object_id)) + N' REBUILD;'
FROM sys.indexes i
WHERE i.object_id = @oid
  AND i.type = 2
  AND i.is_disabled = 1;

-- Re-materialize the SIFT views first would be pointless before the data is there, but they must be
-- rebuilt here : while disabled, any BC query using WITH (NOEXPAND) on them fails.
SELECT @cmd = @cmd + N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON '
            + QUOTENAME(SCHEMA_NAME(v.schema_id)) + N'.' + QUOTENAME(v.name) + N' REBUILD;'
FROM sys.views v
JOIN sys.indexes i ON i.object_id = v.object_id AND i.type = 1 AND i.is_disabled = 1
WHERE EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
              WHERE d.referencing_id = v.object_id AND d.referenced_id = @oid);

IF @cmd <> N'' EXEC sp_executesql @cmd;

SELECT (SELECT COUNT(*) FROM sys.indexes
        WHERE object_id = @oid AND type = 2 AND is_disabled = 1)
     + (SELECT COUNT(*) FROM sys.views v
        JOIN sys.indexes i ON i.object_id = v.object_id AND i.type = 1 AND i.is_disabled = 1
        WHERE EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
                      WHERE d.referencing_id = v.object_id AND d.referenced_id = @oid));";

            return ExecuteIndexCommand(connectionString, tableName, sql);
        }

        private static int ExecuteIndexCommand(string connectionString, string tableName, string sql)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
                throw new ArgumentException("ConnectionString must be set", nameof(connectionString));
            if (string.IsNullOrWhiteSpace(tableName))
                throw new ArgumentException("Table name must be set", nameof(tableName));

            // Unknown table (the $ext table does not always exist) : nothing to do
            if (!TableExists(connectionString, tableName))
                return 0;

            using (var connection = new SqlConnection(connectionString))
            {
                connection.Open();
                using (var command = new SqlCommand(sql, connection))
                {
                    command.CommandTimeout = 0; // a rebuild on a large table can run for a long time
                    command.Parameters.AddWithValue("@table", tableName.Trim());
                    object result = command.ExecuteScalar();
                    return result == null || result == DBNull.Value ? 0 : Convert.ToInt32(result);
                }
            }
        }

        private DataTable CreateSubset(DataTable source, List<string> columnNames)
        {
            DataTable dt = new DataTable();

            foreach (string colName in columnNames)
            {
                DataColumn sourceCol = source.Columns[colName];
                dt.Columns.Add(colName, sourceCol.DataType);
            }

            foreach (DataRow srcRow in source.Rows)
            {
                DataRow newRow = dt.NewRow();
                foreach (string col in columnNames)
                {
                    newRow[col] = srcRow[col];
                }
                dt.Rows.Add(newRow);
            }

            return dt;
        }

        private byte[] CompressForBusinessCentral(byte[] rawData)
        {
            // Compress Blob stream using Deflate
            // Reproduce BC behavious for Blob table fields SQL storage
            if (rawData == null || rawData.Length == 0)
                return new byte[0];  // Empty – no header needed

            // Quick check: does it already start with the BC magic header?
            byte[] magicHeader = new byte[] { 2, 69, 125, 91 }; 
            if (rawData.Length >= magicHeader.Length &&
                StartsWithMagic(rawData, magicHeader))
            {
                // Already BC-compressed format → return as-is
                return rawData;
            }
            
            
            System.IO.MemoryStream compressedStream = new System.IO.MemoryStream();

            // Prepend BC magic header
            compressedStream.Write(magicHeader, 0, magicHeader.Length);

            // Compress the rest with Deflate (no extra headers like GZip)
            using (var deflate = new DeflateStream(compressedStream, CompressionMode.Compress, true))
            {
                deflate.Write(rawData, 0, rawData.Length);
            }

            return compressedStream.ToArray();
        }

        private static bool StartsWithMagic(byte[] data, byte[] magic)
        {
            for (int i = 0; i < magic.Length; i++)
            {
                if (data[i] != magic[i])
                    return false;
            }
            return true;
        }

        private static bool TableExists(string connectionString, string tableName)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
                throw new ArgumentException("ConnectionString must be set", nameof(connectionString));

            if (string.IsNullOrWhiteSpace(tableName))
                throw new ArgumentException("Table name must be set", nameof(tableName));

            // Protection basique contre injection (même si on utilise des paramètres)
            tableName = tableName.Trim();

            const string sql = @"
            SELECT 1 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_NAME = @table 
              AND TABLE_TYPE = 'BASE TABLE'";

            try
            {
                var connection = new SqlConnection(connectionString);
                connection.Open();

                var command = new SqlCommand(sql, connection);
                command.Parameters.AddWithValue("@table", tableName);

                var result = command.ExecuteScalar();
                connection.Close();
                return result != null;
            }
            catch (SqlException ex)
            {
                // 4060 = Cannot open database, 18456 = login failed, etc.
                if (ex.Number == 4060 || ex.Number == 18456 || ex.Number == 53)
                {
                    throw new InvalidOperationException("Unable to connect to the database.", ex);
                }
                throw;
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Unable to verify table existence for : '{tableName}'", ex);
            }
        }

        public int RowCount
        {
            get { return _dataTable.Rows.Count; }
        }
    }
}