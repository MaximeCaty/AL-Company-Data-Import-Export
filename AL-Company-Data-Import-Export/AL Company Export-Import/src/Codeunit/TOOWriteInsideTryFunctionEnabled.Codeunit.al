codeunit 51010 "TOO WriteInsideTryEnabled"
{
    trigger OnRun()
    var
        Buffer: Record "Name/Value Buffer";
        EnvironmentInformation: Codeunit "Environment Information";
    begin
        if EnvironmentInformation.IsSaaS() then
            exit; // Write inside tryfunction is alway enabled on SaaS

        // Test write inside a tryfunction
        Buffer.DeleteAll();
        Buffer.Init();
        Buffer.ID := 1892256;
        if not TryInsert(Buffer) then
            Error('');
        Buffer.Delete();
        exit;
    end;

    [TryFunction]
    local procedure TryInsert(Buffer: Record "Name/Value Buffer")
    begin
        Buffer.Insert();
    end;
}