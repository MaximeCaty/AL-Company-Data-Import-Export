codeunit 51007 "TOO Pipou Import Events"
{
    // This codeunit is subscribed manualy during data-import via AL
    // it aim to ignore insert events to let the raw data be imported without logic process
    // add your own subscriber here as wanted

    EventSubscriberInstance = Manual;

    var
        ImportingRecordID: RecordId;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::GlobalTriggerManagement, OnBeforeOnDatabaseInsert, '', false, false)]
    local procedure OnBeforeOnDatabaseInsert(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;


    procedure SetRecordID(RecID: RecordId)
    begin
        ImportingRecordID := RecID;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Change Log Management", OnBeforeLogInsertion, '', false, false)]
    local procedure OnBeforeLogInsertion(var RecRef: RecordRef)
    begin
        if RecRef.RecordId = ImportingRecordID then begin
            // Ignore change log on record beeing imported
            // change event recref as temporary (this doesnt change the real record beeing inserted tho)
            RecRef.Close();
            RecRef.Open(ImportingRecordID.TableNo, true);
        end;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Contact Business Relation", OnInsertOnBeforeFindByContact, '', false, false)]
    local procedure ContactOnInsertOnBeforeFindByContact(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Contact Business Relation", OnInsertOnBeforeFindByRelation, '', false, false)]
    local procedure ContactOnInsertOnBeforeFindByRelation(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::customer, OnBeforeCreateNewCustomer, '', false, false)]
    local procedure CustomerOnBeforeCreateLink(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::vendor, OnBeforeCreateNewVendor, '', false, false)]
    local procedure VendorOnBeforeCreateLink(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::Customer, OnBeforeInsert, '', false, false)]
    local procedure CustomerOnBeforeInsert(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::Vendor, OnBeforeOnInsert, '', false, false)]
    local procedure VendorOnBeforeOnInsert(var IsHandled: Boolean)
    begin
        IsHandled := true;
    end;
}
