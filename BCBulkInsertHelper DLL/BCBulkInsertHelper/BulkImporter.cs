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

        public void AddRowValueALDate(int Year, int Month, int Day, int columnIndex)
        {
            if (Year <= 1753) // this catches 0DT from AL
            {
                _currentRow[columnIndex] = ALBlankDateTime;
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

        public void WriteToServer(string connectionString, string mainTableName, int batchSize = 10000)
        {            
            if (_dataTable.Rows.Count == 0)
                return;

            // Detect field from table extnesion (ending with $ + app guid)
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
                using (var bulk = new SqlBulkCopy(connectionString, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.TableLock))
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
                 using (var bulk = new SqlBulkCopy(connectionString, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.TableLock))
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