table 51016 "TOO All Types"
{
    DataClassification = ToBeClassified;
    TableType = Temporary;


    fields
    {
        field(1; PK; Code[10])
        {
            DataClassification = SystemMetadata;
        }

        field(10; Text; Text[1])
        {
            DataClassification = SystemMetadata;
        }
        field(11; Code; Code[1])
        {
            DataClassification = SystemMetadata;
        }
        field(12; Date; Date)
        {
            DataClassification = SystemMetadata;
        }
        field(13; Time; Time)
        {
            DataClassification = SystemMetadata;
        }
        field(14; DateTime; DateTime)
        {
            DataClassification = SystemMetadata;
        }
        field(15; Integer; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(16; BigInteger; BigInteger)
        {
            DataClassification = SystemMetadata;
        }
        field(17; Decimal; Decimal)
        {
            DataClassification = SystemMetadata;
        }
        field(18; Duration; Duration)
        {
            DataClassification = SystemMetadata;
        }
        field(19; RecordID; RecordId)
        {
            DataClassification = SystemMetadata;
        }
        field(20; DateFormula; DateFormula)
        {
            DataClassification = SystemMetadata;
        }
        field(22; TableFilter; TableFilter)
        {
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        key(Key1; PK)
        {
            Clustered = true;
        }
    }
}