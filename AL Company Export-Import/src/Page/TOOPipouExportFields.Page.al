page 51000 "TOO Pipou Export Fields"
{
    PageType = List;
    SourceTable = "TOO Pipou Archive fields";
    InsertAllowed = false;
    ModifyAllowed = false;
    Caption = 'Tables Fields';
    SourceTableTemporary = true;

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Field ID"; Rec."Field ID") { Editable = false; }
                field("Field Name"; Rec."Field Name") { Editable = false; }
                field("Field Caption"; Rec."Field Caption") { Editable = false; }
                field("Field Type"; Rec."Field Type") { Editable = false; }
                field("Max Length"; Rec."Max Length") { Editable = false; }
            }
        }
    }

    procedure SetTempFields(var Temp: Record "TOO Pipou Archive Fields" temporary)
    begin
        Rec.Copy(Temp, true);
        CurrPage.Update(false);
    end;
}