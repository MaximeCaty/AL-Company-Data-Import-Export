
# AL Company Data-Import-Export


Remember when we could use this NAV  "Import/Export Data File" top copy company betwen production and test environment ?

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/NavExportData.png?raw=true)

This does not exists anymore in Business Central. 
Only an old powershell command remain and is very unconvenient to use 
(Slow, no visible progression, fail at the first schema difference)

So here is an AL version of Import-Export data file, with offer superior ability than the legacy version.

2. **Partial company data** selection possible for export/import (you may exclude tables like logs to limit data size)
3. **Support schema difference** at import : auto suggest table and field matching with manual control
4. **Assisted page** for import/export with GUI process progression
5. **Error handling** : the process continue on next data chunk when an error occur
6. **Optimised performance** with multithreading
8. **Restricted file size** using combination of binary encoding, column oriented storage and advanced compression

### Usage SaaS vs On-Premise Limitations

- **File Size** : much bigger file in SaaS, as it use Gzip while OnPremise can use more efficient compression (~40% difference)
- **Performance** : Cloud import using AL "Record" insert, is about 3x slower than On-Premise when using direct SQL bulk insert DLL.
- **System Fields** : Can't be imported in SaaS (filled with current user/datetime). Can be import On-Premise with SQL bulk insert DLL.

## Export 

Search for the page "Assisted company data export" :

Steps :
1. Select the company to export. Estimation of file size and export are calculated for On-Prem configuration.
2. Choose data selection rule : classified data, system fields, global data, logs, archive.
4. Archive format, leave "Auto" for the optimal performance/file size ratio.
5. Review the list of tables that will be exported. You can remove table from this list.
6. Review summary, lower the number of threads if you want to reduce server workload, press "Start Export"

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Export-UI.png?raw=true)

## Import 

Create a new blank company first.

Then search for the page "Assisted company data import"

1. Upload an archive file. The system read metadata and prepare tables files to import.
2. Select the destination company to import and review Archive file informations.
3. Review the list of table to import and matching status. For each table you can review field matching individualy and adapt the default suggestion.
4. Enable truncate table before importing for a clean import.
5. Review summyarz, lower the number of threads if you want to reduce server workload. press "Start Import"


## Deployment & Installation

- **SaaS** :
in ```app.json``` remove "ONPREM" pragma :
  ```
  "preprocessorSymbols": [
    "ONPREM"
  ]
  ```
  You can then package the app in cloud compatible version 
  And manualy upload the app in your instance. 

-  **On-Premise** : 
1. Copy DLLs from ```.netpackages``` in your Business Central Addin folder. 
2. Restart Business Central instance. 
3. Then publish the app with the "ONPREM" pragma

- **Recommanded for much better compression :** copy bsc.exe in the Busienss Central Addin folder.  The app will use it when available to further reduce file size.
This executable can be found here [GitHub Libbsc release](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12) 

## Archive File Format & Encoding

This chapter explain how the data is structured inside archive files.

### Options offered in the assisted export


  - **Auto (On-Premise)** : Use zStd for < 1Mb files, then libbsc for larger file, if installed. Max. file chunk is 75 MB to limit ram usage. Optimal binary encoding = **disabled**, System fields = **included**

  - **Auto (SaaS)** : Use Gzip, Max. file chunk is 200 MB. Optimal binary encoding = **enabled**, System fields =**skiped**

  - **Gzip** : Compress with gzip at "optimal" level, other options are manual

  - **zStd** : Compress with zStandard at medium level (12/22), other options are manual

  - **Libbsc** : Compress with bsc.exe at medium level (1/2), other options are manual


### Archive structure 
```
Archive.zip/
|   datameta.json      // definition of tables schemas, files ansd general info
|   Table1_File1.gzip  // Table chunk, row-oriented binary 
|   Table1_File2.gzip  // Table chunk, row-oriented binary
|   Table2_File1.gzip  // Table chunk, row-oriented binary
...
|   Table18_File1.colstore.bsc/  // Table chunk, column-oriented, compressed TAR file
|   |   +-- columns.json         // field-column file info.
|   |   +-- Column_1.bin         // table column binary data
|   |   +-- Column_2.bin
...
```


### How data is encoded

All business central data are written in binary format. 

The data is not human readable, but allow faster performance and smaller files than text based data such as CSV. 

**Binaries stream contain only table data**, without any headers or separators. 
The stream is read with exact same logic than it was created, based on the exported table schema. A single bit difference will throw an error when importing.

To enforce the data integrity, an **MD5 hash is verified after each file is decompressed**. 


## Row-oriented

The system automatically use this format for tables with < 100 records.

**Row-oriented is better suited for small table**, because it does not have the column managment overhead.

Each table record is written as a "row" composed of all the field binary values.

The file does not contain any metadata, separators or control character.


## Column oriented (parquet-like format)

The system automatically use this format when enabled, for tables with >= 100 records.

**Column-oriented is better suited for large table**, it increase compression ratio and improve import speed when some columns are empty or unused.

Each columns are stored as separate binary stream inside a TAR archive. A json file is stored along in the TAR to retrieve columns definition.

When exporting column-orentied data, the program automaticaly detect empty column.

At the export end, empty columns are ignored therefore reducing the file size.

The final TAR file is compressed as one single file, achieving better ratio than row-oriented file, due to better data-pattern groupment.

## Table chunking

A size limit is fixed per file in order to limit maximal RAM usage, and distribute database comits.

When the in memory export file reach the limit, it is closed, compressed then stored and a new file start for the ongoing table records.

## Optimal binary encoding

Reduce the number of bytes needed to write numericals values. 

This option allow to reduce final file size with basic compressor such as Gzip :

See original repository : [AL-Optimal-Binary-Encoding details](https://github.com/MaximeCaty/AL-Optimal-Binary-Encoding)

**This option is not recommanded when using Libbsc compression** because it can increase the final file size with uncecessary processing overhead.







