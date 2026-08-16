#if ONPREM
dotnet
{
    //MemoryStream
    assembly("Microsoft.Data.SqlClient")
    {

        type("Microsoft.Data.SqlClient.SqlConnection"; TOOSqlConnection) { }
        type("Microsoft.Data.SqlClient.SqlCommand"; TOOSqlCommand) { }
        type("Microsoft.Data.SqlClient.SqlDataReader"; TOOSqlDataReader) { }
    }

    assembly("Microsoft.Dynamics.Nav.NavUserAccount")
    {
        type("Microsoft.Dynamics.Nav.NavUserAccount.NavUserAccountHelper"; TOONavUserAccountHelper) { }
    }
    assembly("BCBulkInsertHelper")

    {
        type("BCBulkInsertHelper.BulkImporterExt"; TOOSQLBulkImporterExt) { }
    }
    assembly("ZstdNet")
    {
        type("ZstdNet.Decompressor"; TOOZstdDecompressor) { }
        type("ZstdNet.Compressor"; TOOZstdCompressor) { }
        type("ZstdNet.CompressionOptions"; TOOZstdCompressionOptions) { }
    }
    assembly("mscorlib")
    {
        type("System.Array"; "Array") { }
        type("System.Byte"; "Byte") { }
        type("System.Type"; "Type") { }
        type("System.IO.Stream"; "Stream") { }
        type("System.IO.MemoryStream"; "MemoryStream") { }
    }

    assembly("System")
    {
        type("System.Diagnostics.Process"; TOOProcess) { }
        type("System.Diagnostics.ProcessStartInfo"; TOOProcessStartInfo) { }
    }
}
#endif