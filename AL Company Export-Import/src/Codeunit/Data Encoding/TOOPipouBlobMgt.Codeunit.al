codeunit 51006 "TOO Pipou Blob Mgt."
{
    #region Imprt BLOB

    procedure ImportBlobBinData(var FieldRef: FieldRef; var InStr: InStream)
    var
        Length: Integer;
        TempBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
    begin
        InStr.Read(Length);
        if Length > 0 then begin
            TempBlob.CreateOutStream(OutStr);
            CopyStream(OutStr, InStr, Length);
            TempBlob.ToFieldRef(FieldRef);
        end;
    end;

    procedure ImportBlobData(var FieldRef: FieldRef; Value: Text)
    var
        TempBlob: Codeunit "Temp Blob";
        B64: Codeunit "Base64 Convert";
        OutStream: OutStream;
        CR: Text[1];
        LF: Text[1];
    begin
        if Value = '' then exit;
        FieldRef.CalcField();
        TempBlob.CreateOutStream(OutStream);
        CR[1] := 13;
        LF[1] := 10;
        Value := Value.Replace('~\r', CR).Replace('~\n', LF);
        B64.FromBase64(Value, OutStream);
        TempBlob.ToFieldRef(FieldRef);
    end;
    #endregion

    #region Exprt BLOB
    procedure ExportBlobFieldBinary(var FieldRef: FieldRef; var OutStr: OutStream; BlobMaxSize: Integer) Length: Integer
    var
        TempBlob: Record "TOO Temp Blob" temporary;
        BlobInStr: InStream;
    begin
        // This is much faster than using TempBlob.FromFieldRef(FieldRef)
        // TempBlob.FromFieldRef is doing 2 SQL fetch on the blob (if not hasvalue then calcfield + create instream)
        // Blob meta is already fetched (setloadfield/setautocalcfields) so we dont need to redo a calcfield 
        TempBlob.Blob := FieldRef.Value();
        if not TempBlob.Blob.HasValue then begin // HasValue is true when retrieved from db, even if the blob is empty
            // Fallback when not been added in setautocalcfields()
            FieldRef.CalcField();
            TempBlob.Blob := FieldRef.Value();
        end;
        if (TempBlob.Blob.Length() > BlobMaxSize) or (TempBlob.Blob.Length() = 0) then
            OutStr.Write(0)
        else begin
            OutStr.Write(TempBlob.Blob.Length());
            TempBlob.Blob.CreateInStream(BlobInStr);
            CopyStream(OutStr, BlobInStr);
        end;
        exit(TempBlob.Blob.Length());
    end;
    #endregion


    #region Imprt Media

    procedure ImportMediaSetBinary(var MediaSetGuid: Guid; var InStr: InStream)
    var
        TenantMediaSet: Record "Tenant Media Set";
        MediaCount: Integer;
        MediaGuid: Guid;
        MediaIndex: BigInteger;
        I: Integer;
    begin
        // Media count, ID, (Media Index, Guid, Mime Type, Width, Height, Desciption, Content)[n]
        InStr.Read(MediaCount);
        if MediaCount > 0 then begin
            InStr.Read(MediaSetGuid);
            for I := 1 to MediaCount do begin
                InStr.Read(MediaIndex);
                ImportMediaBinary(MediaGuid, InStr);
                TenantMediaSet.Init();
                TenantMediaSet.ID := MediaSetGUID;
                Evaluate(TenantMediaSet."Media ID", MediaGUID);
                TenantMediaSet."Media Index" := MediaIndex;
                if not TenantMediaSet.Insert(false) then
                    TenantMediaSet.Modify();
            end;
        end;
    end;

    procedure ImportMediaBinary(var MediaGuid: Guid; var InStr: InStream)
    var
        OutStr: OutStream;
        TenantMedia: Record "Tenant Media";
        Length: Integer;
        Text: Text;
        Int: Integer;
    begin
        InStr.Read(Length);
        if Length > 0 then begin
            InStr.Read(MediaGuid);
            // Guid, Mime Type, Width, Height, Desciption, Content
            TenantMedia.Init();
            TenantMedia.ID := MediaGUID;
            InStr.Read(Text);
            TenantMedia."Mime Type" := Text;
            InStr.Read(Int);
            TenantMedia.Width := Int;
            InStr.Read(Int);
            TenantMedia.Height := Int;
            InStr.Read(Text);
            TenantMedia.Description := Text;
            TenantMedia.Content.CreateOutStream(OutStr);
            CopyStream(OutStr, InStr, Length);
            if not TenantMedia.Insert() then
                TenantMedia.Modify();
        end;
    end;
    #endregion


    #region Exprt Media
    procedure ExportMediaSetFieldBinary(TenantMediaSetGuid: Guid; var OutStr: OutStream)
    var
        MediaId: Guid;
        TenantMediaSet: Record "Tenant Media Set";
    begin
        TenantMediaSet.SetRange(ID, TenantMediaSetGuid);
        if TenantMediaSet.IsEmpty() then
            OutStr.Write(0)
        else begin
            // Number of medias
            OutStr.Write(TenantMediaSet.Count());
            // Mediaset guid
            OutStr.Write(TenantMediaSetGuid);
            TenantMediaSet.FindSet();
            repeat
                MediaId := TenantMediaSet."Media ID".MediaId;
                OutStr.Write(TenantMediaSet."Media Index");
                ExportMediaFieldBinary(MediaId, OutStr);
            until TenantMediaSet.Next() = 0;
        end;
    end;

    procedure ExportMediaFieldBinary(MediaId: Guid; var OutStr: OutStream)
    var
        BlobInStr: InStream;
        TenantMedia: Record "Tenant Media";
        BlobLen: Integer;
    begin
        TenantMedia.SetAutoCalcFields(Content);
        if not TenantMedia.Get(MediaId) then begin
            OutStr.Write(0);
            exit;
        end;
        //TenantMedia.CalcFields(Content);
        BlobLen := TenantMedia.Content.Length;
        if BlobLen = 0 then
            OutStr.Write(0)
        else begin
            OutStr.Write(BlobLen);
            OutStr.Write(TenantMedia.ID);
            OutStr.Write(TenantMedia."Mime Type");
            OutStr.Write(TenantMedia.Width);
            OutStr.Write(TenantMedia.Height);
            OutStr.Write(TenantMedia.Description);
            TenantMedia.Content.CreateInStream(BlobInStr);
            CopyStream(OutStr, BlobInStr);
        end;
    end;
    #endregion
}