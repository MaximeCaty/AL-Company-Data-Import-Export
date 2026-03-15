codeunit 51007 "TOO Pipou Import Events"
{
    // This codeunit subscribe manualy to events when importing company data via AL
    // it aim to ignore as much insert events as possible to let the raw data be imported without logic process

    EventSubscriberInstance = Manual;


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

    [EventSubscriber(ObjectType::Table, Database::Contact, OnBeforeCreateLink, '', false, false)]
    local procedure ContactOnBeforeCreateLink(var IsHandled: Boolean)
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