codeunit 51000 "TOO WriteInsideTryEnabled"
{
    trigger OnRun()
    var
        Buffer: Record "Name/Value Buffer";
    begin
#if ONPREM
        Buffer.DeleteAll();
        Buffer.Init();
        Buffer.ID := 1892256;
        if not TryInsert(Buffer) then
            Error('');
        Buffer.Delete();
#else
        exit; // Write inside tryfunction is alway enabled on SaaS
#endif
    end;

    [TryFunction]
    local procedure TryInsert(Buffer: Record "Name/Value Buffer")
    begin
        Buffer.Insert();
    end;
}