/*
    Used to export RecRef blobs faster than converting fieldref to a "temp blob" codeunit
*/
table 51014 "TOO Temp Blob"
{
    Access = Internal;
    DataClassification = SystemMetadata;
    TableType = Temporary;

    fields
    {
        field(1; "Primary Key"; Integer) { }
        field(2; "Blob"; Blob) { }
    }
    keys
    {
        key(Key1; "Primary Key")
        {
            Clustered = true;
        }
    }
}

