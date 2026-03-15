table 51005 "TOO Pipou Import Log"
{
    DataClassification = CustomerContent;
    LookupPageId = "TOO Pipou Import Logs";
    DrillDownPageId = "TOO Pipou Import Logs";
    DataPerCompany = false;

    fields
    {
        field(1; "Entry No."; Integer)
        {

        }
        field(2; "Archive Name"; Text[150])
        {

        }
        field(3; "Archive ID"; Guid)
        {

        }
        field(4; "Thread No."; Integer)
        {

        }
        field(10; "Chunk Entry No."; Text[50])
        {

        }
        field(15; "Table ID"; Integer)
        {

        }
        field(16; "Table Name"; Text[30])
        {
            TableRelation = "Table Metadata".Name where(ID = field("Table ID"));
        }

        field(20; "Record ID"; RecordID)
        {
        }
        field(30; "Action"; Option)
        {
            OptionMembers = " ","Clear Table","Insert Record","Parsing Field","Commit","AL Code";
        }
        field(40; Status; Option)
        {
            OptionMembers = " ","Warning","Error","Information";
        }
        field(50; "Message"; Text[2048])
        {

        }
        field(60; "CallStack"; Text[2048])
        {

        }
    }

    keys
    {
        key(Key1; "Archive Name", "Archive ID", "Entry No.", "Thread No.")
        {
            Clustered = true;
        }
    }
}