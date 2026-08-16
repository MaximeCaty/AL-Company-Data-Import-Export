page 51011 "TOO Pipou Export Tables Sub"
{
    ApplicationArea = All;
    Caption = 'Tables to export';
    InsertAllowed = false;
    PageType = ListPart;
    SourceTable = "TOO Pipou Archive Tables";
    SourceTableTemporary = true;

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Table ID"; Rec."Table ID")
                {
                    Editable = false;
                }
                field("Table Name"; Rec."Table Name")
                {
                    Editable = false;
                }
                field("Table Caption"; Rec."Table Caption")
                {
                    Editable = false;
                }
                field(DataPerCOompany; Rec.DataPerCompany)
                {
                    Editable = false;
                }
                field("No. Records"; Rec."No. of Records")
                {
                    Editable = false;
                }
                field(NoOfFields; NoOfFields)
                {
                    Caption = 'No. of Fields';
                    Editable = false;

                    trigger OnDrillDown()
                    var
                        Fields: Page "TOO Pipou Export Fields";
                    begin
                        TempArchiveTableFields.SetRange("Table ID", Rec."Table ID");
                        Fields.SetTempFields(TempArchiveTableFields);
                        Fields.SetTableView(TempArchiveTableFields);
                        Fields.RunModal();
                        TempArchiveTableFields.Reset();
                    end;
                }
            }
        }
    }

    procedure SetTempTables(var Temp: Record "TOO Pipou Archive Tables" temporary)
    begin
        Rec.Copy(Temp, true);
        CurrPage.Update(false);
    end;

    procedure SetTempFields(var Temp: Record "TOO Pipou Archive Fields" temporary)
    begin
        TempArchiveTableFields.Copy(Temp, true);
    end;

    trigger OnAfterGetRecord()
    begin
        TempArchiveTableFields.SetRange("Table ID", Rec."Table ID");
        NoOfFields := TempArchiveTableFields.Count();
    end;

    var
        TempArchiveTableFields: Record "TOO Pipou Archive Fields" temporary;
        NoOfFields: Integer;
}