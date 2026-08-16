table 51020 "TOO Pipou Archive Dict."
{
    // FK dictionary : the primary key values of a parent table are exported once here, and every child Code/Text
    // column that has an unconditional TableRelation to that parent stores a 1-based ordinal into this stream
    // instead of the literal value. Ordinal 0 = blank, negative/255 = sentinel meaning "literal follows inline".
    // Import reads the stream once into a flat List of [Text] : List.Get is roughly 8x faster than reading the
    // literal back from the column stream, and the archive is ~10 bytes per FK cell smaller.
    Caption = 'Pipou Archive Dictionary', Comment = 'Dictionnaire d''archive Pipou';
    DataClassification = SystemMetadata;
    DataPerCompany = false;

    fields
    {
        field(1; "Archive ID"; Guid) { }
        field(10; "File Name"; Text[70]) { } // sanitized "<ParentTable>$<ParentPKField>", matches "TOO Pipou Archive Fields"."Dictionary File Name"
        field(15; "Field No."; Integer) { }  // parent primary key field whose values the dictionary holds
        field(20; "Table No."; Integer) { }  // parent table : the build groups by it, and it is what the rebuild reads
        field(25; "Dedup Values"; Boolean) { } // parent primary key has several fields : the column repeats, only distinct values are kept
        field(30; "Entry Count"; Integer) { }
        field(40; "Built At"; DateTime) { } // 0DT = planned but not built yet : the reader builds it itself
        field(45; Used; Boolean) { }        // a column actually encoded a value against it : the others are left out of the archive
        field(50; "Thread No."; Integer) { } // export thread that builds it : the one that exports the parent table
        field(55; "Inline Build"; Boolean) { } // filled from the export loop of the parent instead of a read of its own
        field(60; "Option Map"; Boolean) { } // dense byte -> enum member ordinal : pure metadata, no parent table behind it
        field(100; Data; Blob) { Compressed = false; }
    }

    keys
    {
        key(Key1; "Archive ID", "File Name")
        {
            Clustered = true;
        }
        key(ThreadKey; "Archive ID", "Thread No.", "Built At") { }
    }

    var
        OptSetLoaded: Boolean;
        // Shared option set, cached on the record instance : the export and import codeunits hold this record as a
        // global for the whole thread, so every enum of the archive is read from SQL once per thread instead of once
        // per distinct enum per table. Whole thing is a few KB.
        OptSetOrdinals: Dictionary of [Integer, List of [Integer]]; // option id -> real member ordinals
        OptSetArchiveID: Guid;
        OptionNamePrefixTok: Label 'opt$', Locked = true;       // "Dictionary File Name" of an option column : opt$<option id>
        OptionSetFileNameTok: Label 'optionset', Locked = true; // the one shared option dictionary blob of an archive

    #region Naming
    procedure ArchiveEntryName(): Text
    begin
        exit('dict/' + Rec."File Name" + '.bin');
    end;

    local procedure SanitizeName(Name: Text): Text
    begin
        // AL object and field names allow characters that are illegal in file and zip entry names
        exit(Name.Replace('/', '_').Replace('\', '_').Replace(':', '_').Replace('*', '_')
                 .Replace('?', '_').Replace('"', '_').Replace('<', '_').Replace('>', '_')
                 .Replace('|', '_').TrimEnd('.'));
    end;
    #endregion

    #region Eligibility + Flag
    procedure DetectDictionariesFields(var Archive: Record "TOO Pipou Archive")
    var
        Dict: Record "TOO Pipou Archive Dict.";
        ArchField: Record "TOO Pipou Archive Fields";
        ArchTable: Record "TOO Pipou Archive Tables";
        ParentTable: Record "TOO Pipou Archive Tables";
        FldKey: BigInteger;
        ColStoreEnabled: Boolean;
        RelFieldOf: Dictionary of [BigInteger, Integer];  // FieldKey -> RelationFieldNo, whole database
        RelParentOf: Dictionary of [BigInteger, Integer]; // FieldKey -> RelationTableNo, whole database
        FlagDictName: Dictionary of [BigInteger, Text];     // FieldKey -> dictionary file name, the flags of pass 3
        OwnerThreadHasChild: Dictionary of [Integer, Boolean]; // parent -> a consumer table other than itself sits on the owner's thread
        SourceSeen: Dictionary of [Integer, Boolean];       // parent tables already ranked, they are planned once per target
        ParentFirstPK: Dictionary of [Integer, Integer];  // parent table -> first PK field, what RelationFieldNo 0 means
        ParentPKCount: Dictionary of [Integer, Integer];  // parent table -> PK field count, -1 = not usable as a source
        TableRows: Dictionary of [Integer, Integer];
        TableThread: Dictionary of [Integer, Integer];
        ChildRows: Dictionary of [Text, Integer];      // target key -> N, child rows referencing it
        ChildThreads: Dictionary of [Text, Text];      // target key -> ',1,3,' set of exporting threads
        DictNameByTarget: Dictionary of [Text, Text];  // target key -> dictionary file name, built targets only
        TargetFieldName: Dictionary of [Text, Text];   // target key -> parent field name, for the dictionary file name
        ChildTableID: Integer;
        D: Integer;
        I: Integer;
        N: Integer;
        ParentID: Integer;
        T: Integer;
        TargetFieldNo: Integer;
        CandField: List of [Integer];                  // pass 1 hits, replayed by pass 3 instead of scanning again
        CandTable: List of [Integer];
        PassField: List of [Integer];                  // targets that cleared the amortisation gate
        PassParent: List of [Integer];
        CandTarget: List of [Text];
        DictName: Text;
        TargetKeyTxt: Text;
        ThreadMarks: Text;
    begin
        ColStoreEnabled := Archive."Enable Columns Transcoding";
        if not ColStoreEnabled then
            exit;

        // Table metadata cached up front : the passes below need row counts and thread numbers for tables they
        // never position on, and one lookup per candidate field against SQL is what made this slow.
        ArchTable.SetRange("Archive ID", Archive."Archive ID");
        ArchTable.SetLoadFields("Table ID", "No. of Records", "Affected Thread");
        if ArchTable.FindSet() then
            repeat
                TableRows.Set(ArchTable."Table ID", ArchTable."No. of Records");
                TableThread.Set(ArchTable."Table ID", ArchTable."Affected Thread");
            until ArchTable.Next() = 0;

        LoadRelations(RelParentOf, RelFieldOf);

        // Pass 1 : candidate child columns, aggregated per (parent table, parent PK field).
        // One scan of the whole archive field set instead of one filtered scan per table, against relation metadata
        // that was read in a single pass.
        ArchField.SetRange("Archive ID", Archive."Archive ID");
        ArchField.SetFilter("Field Type", '%1|%2', ArchField."Field Type"::Code, ArchField."Field Type"::Text);
        ArchField.SetLoadFields("Table ID", "Field ID");
        if ArchField.FindSet() then
            repeat
                ChildTableID := ArchField."Table ID";
                if IsColumnStored(ColStoreEnabled, TableRows, ChildTableID) then
                    // Missing key = no TableRelation, or a conditional one : RelationTableNo is 0 on those. Any value
                    // that still fails to resolve at export time falls back to the inline literal.
                    if RelParentOf.Get(FieldKey(ChildTableID, ArchField."Field ID"), ParentID) then begin
                        if not ParentPKCount.ContainsKey(ParentID) then
                            CacheParentPK(Archive, ParentID, TableRows, ParentPKCount, ParentFirstPK, TargetFieldName);
                        if ParentPKCount.Get(ParentID) > 0 then begin
                            // The dictionary holds one primary key column of the parent : a relation pointing at any
                            // other field would never resolve. RelationFieldNo 0 = implicit relation to the first PK field.
                            TargetFieldNo := RelFieldOf.Get(FieldKey(ChildTableID, ArchField."Field ID"));
                            if TargetFieldNo = 0 then
                                TargetFieldNo := ParentFirstPK.Get(ParentID);
                            TargetKeyTxt := TargetKey(ParentID, TargetFieldNo);
                            if TargetFieldName.ContainsKey(TargetKeyTxt) then begin
                                if not ChildRows.Get(TargetKeyTxt, N) then
                                    N := 0;
                                ChildRows.Set(TargetKeyTxt, N + TableRows.Get(ChildTableID));
                                if not ChildThreads.Get(TargetKeyTxt, ThreadMarks) then
                                    ThreadMarks := ',';
                                ChildThreads.Set(TargetKeyTxt, AddThreadMark(ThreadMarks, TableThread.Get(ChildTableID)));
                                CandTable.Add(ChildTableID);
                                CandField.Add(ArchField."Field ID");
                                CandTarget.Add(TargetKeyTxt);
                            end;
                        end;
                    end;
            until ArchField.Next() = 0;

        // Pass 2a : amortisation gate
        foreach TargetKeyTxt in ChildRows.Keys() do begin
            SplitTargetKey(TargetKeyTxt, ParentID, TargetFieldNo);
            D := TableRows.Get(ParentID);
            N := ChildRows.Get(TargetKeyTxt);
            T := CountThreadMarks(ChildThreads.Get(TargetKeyTxt));
            // Build cost is paid once per thread that touches the parent (~2720 ns/entry), the import read gain
            // is ~1919 ns/row : profitable above N / (T x D) = 1.42, set conservative x2 to ensure multithread also win
            // Row cap : a dictionary is byte indexed only (MaxDictSourceRows), a bigger parent is never planned.
            // Raise as 1.85 ensure speed gain even for multithreaded and sentinel byte

            // Parent row count above which no dictionary is planned. The ordinal is a single byte : 255 is the sentinel
            // (literal follows inline), 0 is blank, so 254 addressable entries. The synthetic entries add at most one,
            // hence 253 source rows. A wider ordinal was measured to cost more than it saves, and capping here removes
            // the whole size budget and the width plumbing : a dictionary is at most 254 values, always byte indexed.
            if (D > 0) and (D <= 253) and (T > 0) and (N >= 1.86 * T * D) then begin
                PassParent.Add(ParentID);
                PassField.Add(TargetFieldNo);
            end;
        end;

        // Pass 2b : plan one dictionary row per target, do not build any of them here. Reading the parent tables is
        // the whole cost of the preparation and it parallelises : every export thread builds the dictionaries whose
        // parent it exports itself (BuildThreadDictionaries), then starts exporting straight away. A thread that
        // reaches a column encoded against another thread's parent waits for that dictionary on first use.
        for I := 1 to PassParent.Count() do begin
            ParentID := PassParent.Get(I);
            TargetFieldNo := PassField.Get(I);
            if ParentTable.Get(Archive."Archive ID", ParentID) then begin
                TargetKeyTxt := TargetKey(ParentID, TargetFieldNo);

                // "$" as separator : BC's own convention for joining object names in SQL, and it avoids the doubled dot
                // of "Customer.No." + ".bin". Trailing dots are dropped for the same reason.
                DictName := CopyStr(SanitizeName(ParentTable."Table Name") + '$' + SanitizeName(TargetFieldName.Get(TargetKeyTxt)), 1, 70);
                PlanDictionary(Archive, ParentID, TargetFieldNo, CopyStr(DictName, 1, 70),
                                ParentPKCount.Get(ParentID) > 1, BuildingThreadOf(TableThread, ParentID));
                DictNameByTarget.Set(TargetKeyTxt, DictName);
                if not ParentTable."Is Dictionary Source" then begin
                    ParentTable."Is Dictionary Source" := true;
                    ParentTable.Modify();
                end;
            end;
        end;

        // Pass 3a : collect the flags in memory and take the consumer census of each parent. Replays the pass 1
        // hits, so pass 1 and pass 3 can never select a different column set.
        for I := 1 to CandTable.Count() do begin
            TargetKeyTxt := CandTarget.Get(I);
            if DictNameByTarget.Get(TargetKeyTxt, DictName) then
                if DictName <> '' then begin
                    ChildTableID := CandTable.Get(I);
                    FldKey := FieldKey(ChildTableID, CandField.Get(I));
                    FlagDictName.Set(FldKey, DictName);
                    // Consumer census : a dictionary is filled inline only when a consumer sits on the owner's own
                    // thread and reads it right after the parent. A self referencing column is no consumer here,
                    // its dictionary cannot exist while its own table exports.
                    SplitTargetKey(TargetKeyTxt, ParentID, TargetFieldNo);
                    if ChildTableID <> ParentID then
                        if BuildingThreadOf(TableThread, ChildTableID) = BuildingThreadOf(TableThread, ParentID) then
                            OwnerThreadHasChild.Set(ParentID, true);
                end;
        end;

        // Inline build : a dictionary whose parent is exported column oriented and in full is filled straight from
        // the export loop of that parent, so it costs no read of its own, and its table is exported first so it is
        // published as early as possible. No thread ever waits for one : a consumer that finds it unbuilt reads the
        // parent itself, which is at most MaxDictSourceRows rows.
        ArchTable.Reset(); // drops the SetLoadFields of the metadata cache : the rows below are read to be modified
        for I := 1 to PassParent.Count() do begin
            ParentID := PassParent.Get(I);
            // A parent reached through two of its primary key columns is planned twice, it is still one table
            if not SourceSeen.ContainsKey(ParentID) then begin
                SourceSeen.Set(ParentID, true);
                if (TableRows.Get(ParentID) > 100) and OwnerThreadHasChild.ContainsKey(ParentID) then begin
                    Dict.SetRange("Archive ID", Archive."Archive ID");
                    Dict.SetRange("Table No.", ParentID);
                    Dict.SetRange("Option Map", false); // an option map has no parent read to move around
                    Dict.ModifyAll("Inline Build", true);
                    if ArchTable.Get(Archive."Archive ID", ParentID) then begin
                        ArchTable."Export Order" := -1;
                        ArchTable.Modify();
                    end;
                end;
            end;
        end;

        // Pass 3b : flag the child columns whose target got a dictionary. One filtered scan under the pass 1 filter
        // instead of one Get per candidate : the flags are reached by (table, field) in memory.
        if FlagDictName.Count() = 0 then
            exit;
        ArchField.Reset(); // drops the SetLoadFields of pass 1 : the rows below are read to be modified
        ArchField.SetRange("Archive ID", Archive."Archive ID");
        ArchField.SetFilter("Field Type", '%1|%2', ArchField."Field Type"::Code, ArchField."Field Type"::Text);
        if ArchField.FindSet(true) then
            repeat
                FldKey := FieldKey(ArchField."Table ID", ArchField."Field ID");
                if FlagDictName.Get(FldKey, DictName) then begin
                    ArchField."Use Dictionary" := true;
                    ArchField."Dictionary File Name" := CopyStr(DictName, 1, 70);
                    ArchField.Modify();
                end;
            until ArchField.Next() = 0;
    end;

    local procedure PlanDictionary(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer; ParentFieldNo: Integer; FileName: Text[70]; NeedDedup: Boolean; ThreadNo: Integer)
    var
        Dict: Record "TOO Pipou Archive Dict.";
    begin
        // "Built At" stays 0DT : that is what tells the owning thread it still has to build it, and the other
        // threads that it is not readable yet.
        Dict.Init();
        Dict."Archive ID" := Archive."Archive ID";
        Dict."File Name" := FileName;
        Dict."Table No." := ParentTableID;
        Dict."Field No." := ParentFieldNo;
        Dict."Dedup Values" := NeedDedup;
        Dict."Thread No." := ThreadNo;
        if Dict.Insert() then;
    end;

    local procedure BuildingThreadOf(var TableThread: Dictionary of [Integer, Integer]; ParentTableID: Integer): Integer
    var
        ThreadNo: Integer;
    begin
        // The thread that exports the parent builds its dictionary : it is the one whose table range already
        // covers that table, so nothing else has to be balanced.
        if not TableThread.Get(ParentTableID, ThreadNo) then
            exit(1);
        if ThreadNo = 0 then
            exit(1); // single thread export leaves "Affected Thread" at 0
        exit(ThreadNo);
    end;

    local procedure IsColumnStored(ColStoreEnabled: Boolean; var TableRows: Dictionary of [Integer, Integer]; TableID: Integer): Boolean
    var
        Rows: Integer;
    begin
        // Same condition as "TOO Pipou Export Data".ExportTableData : row oriented files are below 100 records,
        // where neither the size nor the read gain is worth a branch per cell.
        if not ColStoreEnabled then
            exit(false);
        if not TableRows.Get(TableID, Rows) then
            exit(false);
        exit(Rows > 100);
    end;

    local procedure LoadRelations(var RelParentOf: Dictionary of [BigInteger, Integer]; var RelFieldOf: Dictionary of [BigInteger, Integer])
    var
        FieldDef: Record Field;
        FldKey: BigInteger;
    begin
        // Every relation of the database in one pass. Filtering the virtual Field table per child table cost one
        // round trip per table of the archive, which is where most of the preparation time went.
        Clear(RelParentOf);
        Clear(RelFieldOf);
        FieldDef.SetRange(Class, FieldDef.Class::Normal);
        FieldDef.SetFilter(RelationTableNo, '<>0');
        // Only a Code or Text child column is ever dictionary encoded (pass 1 filters on the same types) : every
        // other relation of the database is streamed out of the virtual table for nothing.
        FieldDef.SetFilter(Type, '%1|%2|%3|%4', FieldDef.Type::Code, FieldDef.Type::Text, FieldDef.Type::OemCode, FieldDef.Type::OemText);
        if FieldDef.FindSet() then
            repeat
                FldKey := FieldKey(FieldDef.TableNo, FieldDef."No.");
                RelParentOf.Set(FldKey, FieldDef.RelationTableNo);
                RelFieldOf.Set(FldKey, FieldDef.RelationFieldNo);
            until FieldDef.Next() = 0;
    end;

    local procedure FieldKey(TableID: Integer; FieldID: Integer): BigInteger
    begin
        // Field numbers stay below 2^31, so this packs the pair without any collision and without a text allocation
        exit(TableID * 2147483648L + FieldID);
    end;

    local procedure CacheParentPK(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer; var TableRows: Dictionary of [Integer, Integer]; var ParentPKCount: Dictionary of [Integer, Integer]; var ParentFirstPK: Dictionary of [Integer, Integer]; var TargetFieldName: Dictionary of [Text, Text])
    var
        ParentRef: RecordRef;
        FldRef: FieldRef;
        I: Integer;
        Rows: Integer;
        PrimaryKeyRef: KeyRef;
    begin
        ParentPKCount.Set(ParentTableID, -1);
        ParentFirstPK.Set(ParentTableID, 0);
        // The dictionary is built from the exported company : the parent has to be part of the export set
        if not TableRows.Get(ParentTableID, Rows) then
            exit;
        if Rows = 0 then
            exit;
        ParentRef.Open(ParentTableID, false, Archive."Exported From Company");
        PrimaryKeyRef := ParentRef.KeyIndex(1);
        for I := 1 to PrimaryKeyRef.FieldCount do begin
            FldRef := PrimaryKeyRef.FieldIndex(I);
            if I = 1 then
                ParentFirstPK.Set(ParentTableID, FldRef.Number);
            // Integer PK field : the ordinal is as wide as the value it replaces, zero gain
            if FldRef.Type in [FieldType::Code, FieldType::Text] then
                TargetFieldName.Set(TargetKey(ParentTableID, FldRef.Number), FldRef.Name);
        end;
        ParentPKCount.Set(ParentTableID, PrimaryKeyRef.FieldCount);
        ParentRef.Close();
    end;

    local procedure TargetKey(ParentTableID: Integer; ParentFieldNo: Integer): Text
    begin
        exit(Format(ParentTableID) + '|' + Format(ParentFieldNo));
    end;

    local procedure SplitTargetKey(TargetKeyTxt: Text; var ParentTableID: Integer; var ParentFieldNo: Integer)
    var
        SepPos: Integer;
    begin
        SepPos := StrPos(TargetKeyTxt, '|');
        Evaluate(ParentTableID, CopyStr(TargetKeyTxt, 1, SepPos - 1));
        Evaluate(ParentFieldNo, CopyStr(TargetKeyTxt, SepPos + 1));
    end;

    local procedure AddThreadMark(Marks: Text; ThreadNo: Integer): Text
    begin
        if ThreadNo = 0 then
            ThreadNo := 1; // single thread export leaves "Affected Thread" at 0
        if not Marks.Contains(',' + Format(ThreadNo) + ',') then
            Marks += Format(ThreadNo) + ',';
        exit(Marks);
    end;

    local procedure CountThreadMarks(Marks: Text): Integer
    begin
        exit(StrLen(Marks) - StrLen(DelChr(Marks, '=', ',')) - 1);
    end;

    local procedure SyntheticEntries(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer) Values: List of [Text]
    var
        Currency: Record Currency;
        GLSetup: Record "General Ledger Setup";
    begin
        // Add here any value a child column legitimately holds while having no row in the parent table.
        // Must stay deterministic : a dictionary can be rebuilt by any thread that finds it unbuilt, and the two
        // builds have to produce the same ordinals.
        if ParentTableID <> Database::Currency then
            exit;
        // The local currency has no Currency record, but entries store its code literally
        // (Credit Transfer Entry."Currency Code" is almost entirely LCY).
        GLSetup.ChangeCompany(Archive."Exported From Company");
        if not GLSetup.Get() then
            exit;
        if GLSetup."LCY Code" = '' then
            exit;
        Currency.ChangeCompany(Archive."Exported From Company");
        if Currency.Get(GLSetup."LCY Code") then
            exit; // set up as a real currency here, it already has its own ordinal
        Values.Add(GLSetup."LCY Code");
    end;

    #region BuildDict
    procedure BuildThreadDictionaries(var Archive: Record "TOO Pipou Archive"; ThreadNo: Integer; var InlineTables: Dictionary of [Integer, Boolean])
    var
        Dict: Record "TOO Pipou Archive Dict.";
        ParentTable: Record "TOO Pipou Archive Tables";
        NeedDedup: Boolean;
        ParentID: Integer;
        FieldNos: List of [Integer];
        ParentIDs: List of [Integer];
        FileNames: List of [Text];
    begin
        // Called by an export thread before it exports anything : it builds the dictionaries planned on its own
        // tables. Threads therefore split the preparation between them instead of waiting on a single sequential
        // build, and each dictionary is read from the parent exactly once for the whole export.
        // The ones flagged "Inline Build" are not read here at all : their parent fills them from its own export
        // loop. They are only reported back, so the caller knows which of its tables carry that job.
        Clear(InlineTables);
        Dict.SetCurrentKey("Archive ID", "Thread No.", "Built At");
        Dict.SetRange("Archive ID", Archive."Archive ID");
        Dict.SetRange("Thread No.", ThreadNo);
        Dict.SetRange("Built At", 0DT);
        if not Dict.FindSet() then
            exit;
        repeat
            if Dict."Inline Build" then
                InlineTables.Set(Dict."Table No.", true)
            else
                if not ParentIDs.Contains(Dict."Table No.") then
                    ParentIDs.Add(Dict."Table No.");
        until Dict.Next() = 0;

        // Grouped by parent : a parent feeding several dictionaries is read once
        foreach ParentID in ParentIDs do begin
            Clear(FieldNos);
            Clear(FileNames);
            NeedDedup := false;
            Dict.SetRange("Table No.", ParentID);
            if Dict.FindSet() then
                repeat
                    FieldNos.Add(Dict."Field No.");
                    FileNames.Add(Dict."File Name");
                    NeedDedup := NeedDedup or Dict."Dedup Values";
                until Dict.Next() = 0;
            Dict.SetRange("Table No.");

            // Guarded : a parent that is not part of the archive has no rows to read here
            if ParentTable.Get(Archive."Archive ID", ParentID) then
                BuildDictionaries(Archive, ParentID, NeedDedup, FieldNos, FileNames);
        end;
    end;

    procedure GetInlineDictionaries(ArchiveID: Guid; ParentTableID: Integer; var FileNames: List of [Text]; var FieldNos: List of [Integer]; var NeedDedup: Boolean): Boolean
    var
        Dict: Record "TOO Pipou Archive Dict.";
    begin
        // The dictionaries the export loop of this parent has to fill itself. Same shape as the lists BuildDictionaries
        // takes, so both builds write through the same code.
        Clear(FileNames);
        Clear(FieldNos);
        NeedDedup := false;
        Dict.SetRange("Archive ID", ArchiveID);
        Dict.SetRange("Table No.", ParentTableID);
        Dict.SetRange("Inline Build", true);
        Dict.SetRange("Built At", 0DT);
        if not Dict.FindSet() then
            exit(false);
        repeat
            FileNames.Add(Dict."File Name");
            FieldNos.Add(Dict."Field No.");
            NeedDedup := NeedDedup or Dict."Dedup Values";
        until Dict.Next() = 0;
        exit(true);
    end;

    procedure PublishPendingDictionaries(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer)
    var
        Dict: Record "TOO Pipou Archive Dict.";
        NeedDedup: Boolean;
        FieldNos: List of [Integer];
        FileNames: List of [Text];
    begin
        // Safety net of the inline build : a table whose export ended before its record loop (nothing left to export,
        // no exported field, a planned column that turned out not to be exported) never filled its dictionaries.
        // Built here from a read of its own, so no other thread waits for something that is never going to come.
        Dict.SetRange("Archive ID", Archive."Archive ID");
        Dict.SetRange("Table No.", ParentTableID);
        Dict.SetRange("Built At", 0DT);
        if not Dict.FindSet() then
            exit;
        repeat
            FieldNos.Add(Dict."Field No.");
            FileNames.Add(Dict."File Name");
            NeedDedup := NeedDedup or Dict."Dedup Values";
        until Dict.Next() = 0;
        BuildDictionaries(Archive, ParentTableID, NeedDedup, FieldNos, FileNames);
    end;

    procedure BuildDictionaries(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer; NeedDedup: Boolean; FieldNos: List of [Integer]; FileNames: List of [Text]) TotalEntries: Integer
    var
        ParentRef: RecordRef;
        FldRefArr: array[100] of FieldRef;
        Cnt: Integer;
        I: Integer;
        Values: List of [List of [Text]];
        Value: Text;
    begin
        // All the dictionaries of one parent are filled by a single pass over it : a parent referenced through
        // several of its primary key columns used to cost one full read each.
        // No size budget : MaxDictSourceRows caps the parent at 253 rows, so the widest possible dictionary is
        // 254 Text[250] values, well under a hundred kilobytes on every export and import thread.
        Cnt := FieldNos.Count();
        if Cnt > ArrayLen(FldRefArr) then
            Cnt := ArrayLen(FldRefArr);

        ParentRef.Open(ParentTableID, false, Archive."Exported From Company");
        ParentRef.ReadIsolation := ParentRef.ReadIsolation::ReadUncommitted;
        for I := 1 to Cnt do begin
            ParentRef.AddLoadFields(FieldNos.Get(I));
            FldRefArr[I] := ParentRef.Field(FieldNos.Get(I));
            Values.Add(NewValueList()); // fresh instance : AL collections are reference types, a reused variable
        end;                            // would have every list entry point at the same one

        // Primary key order : that order is the contract between export and import, both derive it from this stream
        if ParentRef.FindSet(false) then
            repeat
                for I := 1 to Cnt do begin
                    Value := FldRefArr[I].Value;
                    // A primary key column that is not the whole key repeats : the dictionary only needs the
                    // distinct values, the ordinals still come out of the stream on both sides. Linear Contains
                    // rather than a seen-set : at most 253 rows against at most 254 entries.
                    if NeedDedup then begin
                        if (Value <> '') and not Values.Get(I).Contains(Value) then
                            Values.Get(I).Add(Value);
                    end else
                        Values.Get(I).Add(Value);
                end;
            until ParentRef.Next() = 0;
        ParentRef.Close();

        TotalEntries := WriteDictionaries(Archive, ParentTableID, FileNames, Values);
    end;

    procedure WriteDictionaries(var Archive: Record "TOO Pipou Archive"; ParentTableID: Integer; FileNames: List of [Text]; Values: List of [List of [Text]]) TotalEntries: Integer
    var
        Dict: Record "TOO Pipou Archive Dict.";
        ArchTable: Record "TOO Pipou Archive Tables";
        Cnt: Integer;
        EntryCount: Integer;
        I: Integer;
        Synthetic: List of [Text];
        ValuesOne: List of [Text];
        OutStr: OutStream;
        Value: Text;
    begin
        // Shared tail of both builds : the dedicated read above, and the export loop of the parent when the
        // dictionary is filled inline. Same stream framing and same publication protocol either way.
        Cnt := FileNames.Count();
        if Cnt > Values.Count() then
            Cnt := Values.Count();

        // Values that are legitimately referenced but have no row in the parent, appended after the real ones so
        // the ordinals above keep matching the primary key order
        Synthetic := SyntheticEntries(Archive, ParentTableID);

        // The rows were planned by DetectDictionariesFields : filled here, never inserted.
        // Locked at read time : two threads may rebuild the same parent (ResolveDictionary lets them, the bytes
        // are identical), but an unlocked Get followed by a Modify seconds later - the blob write - fails on the
        // row version the other thread has committed meanwhile, which errors the whole export. The rival now
        // waits on the row and overwrites it after, which is the idempotent outcome that was intended.
        // Lock order is the FileNames order, the same primary key order on both build paths, then the parent
        // table row : no two threads can take them in opposite orders.
        // LockTable alone is not enough : the rows were already read unlocked earlier in this transaction
        // (BuildThreadDictionaries / GetInlineDictionaries / PublishPendingDictionaries), so the Get below is served
        // from the service cache, takes no lock and carries a row version a rival thread has already replaced.
        Dict.LockTable();
        SelectLatestVersion();
        for I := 1 to Cnt do begin
            EntryCount := 0;
            ValuesOne := Values.Get(I);
            Dict.Get(Archive."Archive ID", CopyStr(FileNames.Get(I), 1, 70));
            if ValuesOne.Count() > 0 then begin
                Dict.Data.CreateOutStream(OutStr);
                foreach Value in ValuesOne do begin
                    OutStr.Write(Value); // same text framing as the column streams
                    EntryCount += 1;
                end;
                foreach Value in Synthetic do begin
                    OutStr.Write(Value);
                    EntryCount += 1;
                end;
            end;
            // ponytail: a dictionary that came out empty (its parent was emptied between the plan and the build)
            // stays at 0 entry instead of unflagging its columns, every cell then falls back on the inline literal.
            Dict."Entry Count" := EntryCount;
            Dict.Modify();
            TotalEntries += EntryCount;
        end;
        if TotalEntries > 0 then begin
            ArchTable.LockTable(); // same rival rebuild, same stale Modify
            SelectLatestVersion(); // the export loop read this row unlocked
            if ArchTable.Get(Archive."Archive ID", ParentTableID) then begin
                ArchTable."Dictionary Entry Count" := TotalEntries;
                ArchTable.Modify();
            end;
        end;
        Commit(); // the data has to be committed before "Built At" tells the other threads it is readable

        // "Built At" in its own commit : the other threads probe it uncommitted, so it must never become visible
        // ahead of the blob it announces.
        // Re-locked : the Commit above released the locks of the first loop, and the rows just written are in the
        // cache with the version this transaction wrote, which a rival rebuild has replaced by the time we get here.
        Dict.LockTable();
        SelectLatestVersion();
        for I := 1 to Cnt do begin
            Dict.Get(Archive."Archive ID", CopyStr(FileNames.Get(I), 1, 70));
            Dict."Built At" := CurrentDateTime;
            Dict.Modify();
        end;
        Commit();
    end;
    #endregion

    local procedure NewValueList(): List of [Text]
    begin
    end;
    #endregion

    #region Option dictionaries
    procedure DetectOptionDictionaries(var Archive: Record "TOO Pipou Archive")
    var
        ArchField: Record "TOO Pipou Archive Fields";
        ArchTable: Record "TOO Pipou Archive Tables";
        RecRef: RecordRef;
        FldRef: FieldRef;
        RecRefOpen: Boolean;
        OrdinalsByID: Dictionary of [Integer, List of [Integer]]; // option id -> its member ordinals, written out at the end
        IDBySignature: Dictionary of [Text, Integer]; // member ordinals -> option id, one entry per distinct enum
        CurTableID: Integer;
        DictCount: Integer;
        J: Integer;
        MemberCount: Integer;
        OptionID: Integer;
        Ordinals: array[255] of Integer;
        Rows: Integer;
        Members: List of [Integer];
        Signature: Text;
    begin
        // Option ordinal packing : a member ordinal is written as an Integer although almost every enum of a
        // database holds a handful of values. The dictionary maps a dense 0 based byte back to the real ordinal,
        // which an Enum is free to declare anywhere (the Dataverse mirrored ones sit around 141'030'000, so the
        // dense index cannot simply be the ordinal, nor the ordinal minus a base : they all keep a value(0)).
        // Pure metadata, no table is read to build it : published straight away, and no thread ever waits for one.
        if not Archive."Enable Columns Transcoding" then
            exit;

        ArchField.SetRange("Archive ID", Archive."Archive ID");
        ArchField.SetRange("Field Type", ArchField."Field Type"::Option);
        if not ArchField.FindSet(true) then
            exit;
        repeat
            // Primary key order groups the archive fields per table : the record reference of a table is opened once
            if ArchField."Table ID" <> CurTableID then begin
                CurTableID := ArchField."Table ID";
                Rows := 0;
                if RecRefOpen then begin
                    RecRef.Close();
                    RecRefOpen := false;
                end;
                // Column oriented files only : below 100 records ExportTableData writes row oriented streams,
                // where neither the size nor the read gain is worth a branch per cell.
                if ArchTable.Get(Archive."Archive ID", CurTableID) then
                    if ArchTable."No. of Records" > 100 then begin
                        Rows := ArchTable."No. of Records";
                        RecRef.Open(CurTableID, false, Archive."Exported From Company");
                        RecRefOpen := true;
                    end;
            end;
            if Rows > 0 then begin
                FldRef := RecRef.Field(ArchField."Field ID");
                // No member count on FieldRef : the member list is the only way in, and its position is the
                // 1 based index GetEnumValueOrdinal takes.
                MemberCount := CountOptionMembers(FldRef.OptionMembers);
                // 255 is the sentinel byte, so 255 addressable members (dense 0..254). The ordinal list travels in
                // the archive and is loaded by every import thread : a table with barely more rows than the enum
                // has members would pay more for the dictionary than the three bytes per cell it saves.
                if (MemberCount > 0) and (MemberCount <= 255) and (Rows >= MemberCount * 3) then begin
                    Signature := '';
                    for J := 1 to MemberCount do begin
                        Ordinals[J] := FldRef.GetEnumValueOrdinal(J);
                        Signature += Format(Ordinals[J]) + ',';
                    end;
                    // One entry per distinct enum : the same enum typed on forty tables ships once and is read once
                    // per thread, instead of forty near identical blobs.
                    if not IDBySignature.Get(Signature, OptionID) then begin
                        DictCount += 1;
                        // Numbered rather than named after the column : a shared option map belongs to no single
                        // column anyway, and the number is what addresses it inside the shared blob.
                        OptionID := DictCount;
                        Members := NewIntList();
                        for J := 1 to MemberCount do
                            Members.Add(Ordinals[J]);
                        OrdinalsByID.Set(OptionID, Members);
                        IDBySignature.Set(Signature, OptionID);
                    end;
                    ArchField."Use Dictionary" := true;
                    ArchField."Dictionary File Name" := CopyStr(OptionNamePrefixTok + Format(OptionID), 1, 70);
                    ArchField.Modify();
                end;
            end;
        until ArchField.Next() = 0;
        if RecRefOpen then
            RecRef.Close();

        WriteOptionSet(Archive."Archive ID", OrdinalsByID);
    end;

    local procedure WriteOptionSet(ArchiveID: Guid; var OrdinalsByID: Dictionary of [Integer, List of [Integer]])
    var
        Dict: Record "TOO Pipou Archive Dict.";
        OptionID: Integer;
        Ordinal: Integer;
        Members: List of [Integer];
        OutStr: OutStream;
    begin
        // One blob for every enum of the archive rather than one per enum : the whole thing stays below ~10 KB, and
        // an export or import thread reads a single row instead of one per distinct enum it meets.
        // Format, plain Integer serie : option count, then per option its id, its member count and its ordinals.
        if OrdinalsByID.Count() = 0 then
            exit;
        Dict.Init();
        Dict."Archive ID" := ArchiveID;
        Dict."File Name" := CopyStr(OptionSetFileNameTok, 1, MaxStrLen(Dict."File Name"));
        Dict."Entry Count" := OrdinalsByID.Count();
        Dict."Option Map" := true; // no parent table behind it : the row count guard must skip it
        Dict."Built At" := CurrentDateTime; // metadata only : readable at once, nothing to wait for
        Dict.Used := true; // shipped as soon as one column encodes against it, it is a few KB for the whole archive
        Dict.Insert();
        Dict.Data.CreateOutStream(OutStr);
        OutStr.Write(Dict."Entry Count");
        foreach OptionID in OrdinalsByID.Keys() do begin
            Members := OrdinalsByID.Get(OptionID);
            OutStr.Write(OptionID);
            Ordinal := Members.Count();
            OutStr.Write(Ordinal);
            foreach Ordinal in Members do
                OutStr.Write(Ordinal);
        end;
        Dict.Modify();
    end;

    local procedure NewIntList(): List of [Integer]
    begin
    end;

    local procedure CountOptionMembers(Members: Text) Count: Integer
    var
        InQuotes: Boolean;
        C: Char;
        J: Integer;
    begin
        // A member name holding a space or a comma is double quoted in OptionMembers ("Closed Out"), so a plain
        // Split(',') over counts those and GetEnumValueOrdinal would then be called past the last member.
        if Members = '' then
            exit(0);
        Count := 1;
        for J := 1 to StrLen(Members) do begin
            C := Members[J];
            if C = '"' then
                InQuotes := not InQuotes
            else
                if (C = ',') and not InQuotes then
                    Count += 1;
        end;
    end;

    procedure LoadOptionOrdinals(ArchiveID: Guid; FileName: Text[70]; var Ordinals: array[255] of Integer) MemberCount: Integer
    var
        J: Integer;
        OptionID: Integer;
        Members: List of [Integer];
    begin
        // Dense index -> real ordinal, and both sides read the same array : the import indexes it directly, the
        // export scans it. A flat array rather than a List or a hashtable because the export scan is inlined in the
        // record loop, where crossing the interop boundary once per cell costs more than walking a handful of members.
        LoadOptionSet(ArchiveID); // one SQL read per thread, whatever the number of enums the archive carries
        if not Evaluate(OptionID, FileName.Replace(OptionNamePrefixTok, '')) then
            exit(0);
        if not OptSetOrdinals.Get(OptionID, Members) then
            exit(LoadLegacyOptionOrdinals(ArchiveID, FileName, Ordinals)); // archive written before the shared option set
        MemberCount := Members.Count();
        if MemberCount > ArrayLen(Ordinals) then
            MemberCount := ArrayLen(Ordinals);
        for J := 1 to MemberCount do
            Ordinals[J] := Members.Get(J);
    end;

    local procedure LoadOptionSet(ArchiveID: Guid)
    var
        Dict: Record "TOO Pipou Archive Dict.";
        InStr: InStream;
        J: Integer;
        MemberCount: Integer;
        N: Integer;
        OptionCount: Integer;
        OptionID: Integer;
        Ordinal: Integer;
        Members: List of [Integer];
    begin
        if OptSetLoaded and (OptSetArchiveID = ArchiveID) then
            exit;
        Clear(OptSetOrdinals);
        OptSetLoaded := true;
        OptSetArchiveID := ArchiveID;
        Dict.SetAutoCalcFields(Data); // faster than CalcFields : 1 SQL round trip saved
        if not Dict.Get(ArchiveID, CopyStr(OptionSetFileNameTok, 1, MaxStrLen(Dict."File Name"))) then
            exit; // no option column in this archive, or an archive written before the shared option set
        Dict.Data.CreateInStream(InStr);
        InStr.Read(OptionCount);
        for N := 1 to OptionCount do begin
            InStr.Read(OptionID);
            InStr.Read(MemberCount);
            Members := NewIntList();
            for J := 1 to MemberCount do begin
                InStr.Read(Ordinal);
                Members.Add(Ordinal);
            end;
            OptSetOrdinals.Set(OptionID, Members);
        end;
    end;

    local procedure LoadLegacyOptionOrdinals(ArchiveID: Guid; FileName: Text[70]; var Ordinals: array[255] of Integer) MemberCount: Integer
    var
        Dict: Record "TOO Pipou Archive Dict.";
        InStr: InStream;
        J: Integer;
    begin
        // One blob per enum : how archives were written before the single option set file
        Dict.SetAutoCalcFields(Data);
        if not Dict.Get(ArchiveID, FileName) then
            exit(0); // dropped from the archive : no column ever encoded against it
        Dict.Data.CreateInStream(InStr);
        MemberCount := Dict."Entry Count";
        if MemberCount > ArrayLen(Ordinals) then
            MemberCount := ArrayLen(Ordinals);
        for J := 1 to MemberCount do
            InStr.Read(Ordinals[J]);
    end;
    #endregion

    procedure MarkUsed(ArchiveID: Guid; FileName: Text[70])
    var
        Dict: Record "TOO Pipou Archive Dict.";
    begin
        // Re-read under lock : another thread can flag the same dictionary between the test above and the write,
        // and the Modify then fails on a row version that is no longer the one that was read. The cache has to be
        // dropped with it, otherwise the Get below returns the unlocked read above and locks nothing at all.
        Dict.LockTable();
        SelectLatestVersion();
        if not Dict.Get(ArchiveID, FileName) then
            exit;
        if not Dict.Used then begin
            Dict.Used := true;
            Dict.Modify();
        end;
        Commit(); // one row at a time : the caller marks several dictionaries in a column order that differs per
                  // table, holding them all would deadlock four threads against each other (the "opt$" case)
    end;

    #region Load
    procedure LoadExportDictionary(var Archive: Record "TOO Pipou Archive"; FileName: Text[70]; ThreadNo: Integer) CodeToOrdinal: Dictionary of [Text, Integer]
    var
        Dict: Record "TOO Pipou Archive Dict.";
        InStr: InStream;
        Ordinal: Integer;
        Value: Text;
    begin
        // One hashtable per parent, returned as a fresh instance so the caller can hold several of them in a list.
        // Returning it rather than filling a var parameter matters : AL collections are reference types, reusing
        // one variable to build several dictionaries would have every list entry point at the same instance.
        ResolveDictionary(Archive, FileName, ThreadNo);
        Dict.SetAutoCalcFields(Data); // faster than calcfield : 1 SQL round trip saved
        if not Dict.Get(Archive."Archive ID", FileName) then
            exit; // never planned : every cell of the column falls back on the inline literal
        Dict.Data.CreateInStream(InStr);
        for Ordinal := 1 to Dict."Entry Count" do begin
            InStr.Read(Value);
            CodeToOrdinal.Set(Value, Ordinal);
        end;
    end;

    local procedure ResolveDictionary(var Archive: Record "TOO Pipou Archive"; FileName: Text[70]; ThreadNo: Integer)
    var
        Dict: Record "TOO Pipou Archive Dict.";
    begin
        Dict.ReadIsolation := Dict.ReadIsolation::ReadUncommitted;
        if not Dict.Get(Archive."Archive ID", FileName) then
            exit; // never planned : every cell of the column falls back on the inline literal
        if Dict."Built At" <> 0DT then
            exit;

        // Not built yet : read the parent and build it here, whoever owns it. A dictionary parent is capped at 253
        // rows (MaxDictSourceRows), so a rebuild is a handful of milliseconds - cheaper than any wait, and cheaper
        // than the machinery that decided whether to wait (progress sampling, rent-or-buy budgets).
        // ponytail: two threads reaching the same unbuilt dictionary both read the parent, and the second overwrites
        // the first with the same bytes. Idempotent (same primary key order, same values, so the same ordinals),
        // and cheaper than a lock, which would let two threads deadlock on each other's parent.
        //
        // One exception : filled inline by this very thread, which means the parent is the table being exported
        // right now (a column pointing at its own table, "Bill-to Customer No." and the like). Its ordinals are
        // positions in primary key order and the loop has not reached the higher keys yet, so nothing can be built
        // early. Left unresolved : the caller gets an empty hashtable and sentinels the column, every non blank cell
        // carrying its literal inline, which the import already decodes cell by cell. Blank cells, the bulk of an
        // optional FK column, are ordinal 0 and never look anything up.
        if Dict."Inline Build" and (Dict."Thread No." = ThreadNo) then
            exit;

        PublishPendingDictionaries(Archive, Dict."Table No.");
    end;

    procedure LoadImportDictionary(ArchiveID: Guid; FileName: Text[70]; var FlatValues: List of [Text]) BaseOffset: Integer
    var
        Dict: Record "TOO Pipou Archive Dict.";
        InStr: InStream;
        Ordinal: Integer;
        Value: Text;
    begin
        // Read by ordinal is a direct index : a flat List with a per parent base offset gives one List.Get per cell,
        // no hashing at all. All parents touched by the thread share the list.
        Dict.SetAutoCalcFields(Data);// faster then CalcFields : only one sql roundtrip
        Dict.Get(ArchiveID, FileName);
        Dict.Data.CreateInStream(InStr);
        BaseOffset := FlatValues.Count();
        for Ordinal := 1 to Dict."Entry Count" do begin
            InStr.Read(Value);
            FlatValues.Add(Value);
        end;
    end;
    #endregion
}
