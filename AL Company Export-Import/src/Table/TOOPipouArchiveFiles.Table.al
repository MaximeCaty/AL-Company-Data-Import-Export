table 51004 "TOO Pipou Archive Files"
{
    DataClassification = CustomerContent;
    CompressionType = None; // we already compress the blob
    DataPerCompany = false;
    LookupPageId = "TOO Pipou Archive Files";
    DrillDownPageId = "TOO Pipou Archive Files";

    fields
    {
        field(1; "Archive Name"; Text[150])
        {
            TableRelation = "TOO Pipou Archive"."Archive Name";
            Editable = false;
        }
        field(10; "Archive ID"; Guid)
        {
            TableRelation = "TOO Pipou Archive"."Archive ID" where("Archive Name" = field("Archive Name"));
            Editable = false;
        }
        field(11; "Archive Seq. No."; Integer)
        {
            TableRelation = "TOO Pipou Archive"."Archive Sequence No." where("Archive Name" = field("Archive Name"), "Archive ID" = field("Archive ID"));
            Editable = false;
        }
        field(40; "Table ID"; Integer)
        {
            TableRelation = "Table Metadata";
        }
        field(50; "Table Name"; Text[30])
        {
            TableRelation = "Table Metadata".Name;
        }
        field(60; "Chunk No."; Integer)
        {

        }
        field(70; "File Name"; Text[50])
        {

        }
        field(80; "Start Index"; Integer)
        {

        }
        field(90; "End Index"; Integer)
        {

        }
        field(100; "Number Of Recs"; Integer)
        {

        }
        field(110; "Compression Mode"; Enum "TOO Compression Algo.")
        {
        }
        field(120; "Compressed Length"; Integer)
        {

        }
        field(130; "Comp. Ratio"; Decimal)
        {

        }
        field(140; "Uncompressed Length"; Integer)
        {

        }
        field(150; "Uncompressed MD5 Hash"; Text[150])
        {

        }
        field(160; "Column Storage"; Boolean)
        {

        }
        field(200; Data; Blob)
        {

        }
        field(500; Exported; Boolean)
        {

        }
        field(600; Imported; Boolean)
        {

        }
        field(610; "Table Selected For Import"; Boolean)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Select For Import" WHERE("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
        }
        field(1000; "Original Table Name"; Text[150])
        {
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Table Name" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
            Editable = false;
        }
        field(1010; "Original Table Caption"; Text[150])
        {
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Table Caption" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
            Editable = false;
        }
        field(1020; "No. of Fields"; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("TOO Pipou Archive Fields" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
            Editable = false;
        }
        field(2000; "Affected Thread"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(2020; "Matched Table ID"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Matched Table ID" where("Archive ID" = field("Archive ID"), "Table ID" = Field("Table ID")));
        }
        field(2030; "Matched Status"; Enum "TOO Table Match Status")
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Match Status" where("Archive ID" = field("Archive ID"), "Table ID" = Field("Table ID")));
        }
    }

    keys
    {
        key(Key1; "Archive Name", "Archive ID", "File Name")
        {
            Clustered = true;
        }
        key(SizeSort; "Archive ID", "Uncompressed Length")
        {

        }
        key(SumNbRecsRemaining; "Archive ID", Imported, "Table ID")
        {
            SumIndexFields = "Number Of Recs";
        }
    }
}