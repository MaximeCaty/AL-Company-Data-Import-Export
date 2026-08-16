codeunit 51006 "TOO Pipou Blob Mgt."
{
    #region Imprt BLOB

    procedure ImportBlobBinData(var FieldRef: FieldRef; var InStr: InStream)
    var
        TempBlob: Codeunit "Temp Blob";
        Length: Integer;
        OutStr: OutStream;
    begin
        InStr.Read(Length);
        if Length > 0 then begin
            TempBlob.CreateOutStream(OutStr);
            CopyStream(OutStr, InStr, Length);
        end;
        // Written even when empty : the import loop reuses one record buffer across records,
        // a skipped write would leak the previous record's blob into this one.
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
        MediaIndex: BigInteger;
        MediaGuid: Guid;
        I: Integer;
        MediaCount: Integer;
    begin
        // Media count, ID, (Media Index, Guid, Mime Type, Width, Height, Desciption, Content)[n]
        InStr.Read(MediaCount);
        if MediaCount > 0 then begin
            InStr.Read(MediaSetGuid);
            for I := 1 to MediaCount do begin
                InStr.Read(MediaIndex);
                ImportMediaBinary(MediaGuid, InStr);
                TenantMediaSet.Init();
                TenantMediaSet.ID := MediaSetGuid;
                Evaluate(TenantMediaSet."Media ID", MediaGuid);
                TenantMediaSet."Media Index" := MediaIndex;
                if not TenantMediaSet.Insert(false) then
                    TenantMediaSet.Modify();
            end;
        end else
            // Cleared even when empty : callers pass a reused var, a skipped write would leak the previous value.
            Clear(MediaSetGuid);
    end;

    procedure ImportMediaBinary(var MediaGuid: Guid; var InStr: InStream)
    var
        TenantMedia: Record "Tenant Media";
        Int: Integer;
        Length: Integer;
        OutStr: OutStream;
        Text: Text;
    begin
        InStr.Read(Length);
        if Length > 0 then begin
            InStr.Read(MediaGuid);
            // Guid, Mime Type, Width, Height, Desciption, Content
            TenantMedia.Init();
            TenantMedia.ID := MediaGuid;
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
        end else
            // Cleared even when empty : callers pass a reused var, a skipped write would leak the previous value.
            Clear(MediaGuid);
    end;
    #endregion


    #region Exprt Media
    procedure ExportMediaSetFieldBinary(TenantMediaSetGuid: Guid; var OutStr: OutStream)
    var
        TenantMediaSet: Record "Tenant Media Set";
        MediaId: Guid;
    begin
        if IsNullGuid(MediaId) then begin
            OutStr.Write(0);
            exit;
        end;
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
        TenantMedia: Record "Tenant Media";
        BlobInStr: InStream;
        BlobLen: Integer;
    begin
        if IsNullGuid(MediaId) then begin
            OutStr.Write(0);
            exit;
        end;
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