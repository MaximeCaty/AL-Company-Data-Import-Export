/*
    This temp table allow to export recref blob 
    It is much faster than converting fieldref to codeunit temp blob
*/
table 51014 "TOO Temp Blob"
{
    Access = Internal;
    TableType = Temporary;

    fields
    {
        field(1; "Primary Key"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(2; "Blob"; Blob)
        {
            DataClassification = SystemMetadata;
        }
    }
    keys
    {
        key(Key1; "Primary Key")
        {
            Clustered = true;
        }
    }
}

