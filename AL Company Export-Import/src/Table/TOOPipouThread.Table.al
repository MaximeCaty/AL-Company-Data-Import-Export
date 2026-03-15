table 51009 "TOO Pipou Thread"
{
    DataClassification = ToBeClassified;
    DataPerCompany = false;

    fields
    {
        field(1; "Thread No."; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(10; "Session ID"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(20; "Archive ID"; Guid)
        {
            DataClassification = SystemMetadata;
            TableRelation = "TOO Pipou Archive"."Archive ID";
        }
        field(30; "Archive Name"; Text[150])
        {
            DataClassification = SystemMetadata;
            TableRelation = "TOO Pipou Archive"."Archive Name";
        }
        field(1100; Status; Option)
        {
            DataClassification = SystemMetadata;
            OptionMembers = " ","Starting","Exporting Data","Compressing - Storing","Importing Data","Commiting","Decompressing - Decoding","Completed ✅","❌ Error","Truncating Table";
        }
        field(1105; "Error Message"; Text[2048])
        {
            DataClassification = SystemMetadata;
        }
        field(1110; "Current Table"; Text[30])
        {
            DataClassification = SystemMetadata;
        }
        field(1120; "Current Table Progress %"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(1130; "Current File"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(1140; "Current File Progress %"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(1150; "Total Size To Proceed KB"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(1160; "Proceed Size KB"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(1200; "Total Rec. Proceed"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(1300; "Files Compressed Size (KB)"; Decimal) { DataClassification = SystemMetadata; }
        field(1400; "Files Size (KB)"; Decimal) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(Key1; "Thread No.")
        {
            Clustered = true;
        }
        key(SizeSort; "Total Size To Proceed KB")
        {
        }
        key(SumPerArchiveKey; "Archive ID")
        {
            SumIndexFields = "Total Rec. Proceed", "Files Size (KB)", "Files Compressed Size (KB)";
        }
    }
}