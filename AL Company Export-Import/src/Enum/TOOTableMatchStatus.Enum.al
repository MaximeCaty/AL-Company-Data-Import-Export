enum 51006 "TOO Table Match Status"
{
    Extensible = true;

    value(0; " ")
    {
    }
    value(10; "Full")
    {
        Caption = '✅ Full';
    }
    value(20; "Partial")
    {
        Caption = '⚠️ Partial';
    }
    value(30; "Missing")
    {
        Caption = '⛔ Missing';
    }
}