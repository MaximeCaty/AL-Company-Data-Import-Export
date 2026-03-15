// This table is created to convers handle blob fieldref faster than TempBlob.FromFieldRef(FieldRef)
// TempBlob.FromFieldRef is doing 2 SQL fetch on the blob (if not hasvalue then calcfield + create instream)
// when the Blob meta is already fetched with setloadfield we dont need to redo a calcfield 
table 51014 "TOO Temp Blob"
{
    Access = Internal;
    InherentEntitlements = X;
    InherentPermissions = X;
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

