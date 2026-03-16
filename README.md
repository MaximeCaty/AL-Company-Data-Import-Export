
# AL Company Data-Import-Export


Remember when we could use this NAV  "Import/Export Data File" top copy company betwen production and test environment ?

![Legacy Company Data Import Export](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/NavExportData.png?raw=true)

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

*The app does not support Saas yet : we use "Table Information" to get real data size insight, this table have scope = OnPrem. Feel free to adapt the code if you like to use it on Cloud.*
- **File Size** : much bigger file in SaaS as it use Gzip, while OnPremise can use more efficient compressor (~40% difference with Libbsc)
- **Performance** : Cloud import using native AL inserts, is about 3x slower than doing direct SQL bulk insert with On-Premise DLL.
- **System Fields** : Can't be imported in SaaS (created at/by filled by current user). We can import it On-Premise using direct SQL bulk insert.


## Export 

Search for the page "Assisted company data export" :

Steps :
1. Select the company to export
2. Choose data scope : classified data, system fields, include global data / logs / archive
4. Archive data format ("Auto" by default)
5. Review the list of tables included in export. You may remove table manualy from the list.
6. Review summary, lower number of threads to avoid user freeze while exporting.

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Export-UI.png?raw=true)


## Import 

Create a new blank company first.

Then search for the page "Assisted company data import"

1. Upload an archive, the system read metadata and prepare import
2. Select destination company
3. Review the list of table to import and matching when needed
4. Review summary, lower number of threads to avoid user freeze while importing

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Match.png?raw=true)

*You can change table mapping manually at this step with the column "Matched Table ID". Drill down on the "No. fields" column to change a table field mapping details when needed.*
 - *"⚠️ Partial" mean that some fields are not mapped to the destination table.*
 - *"⛔ Missing" mean that the table is not mapped to a destination table.*

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Progress-Page.png?raw=true)

*Import progress can be either show on a foreground dialog or with this separated page, showing each thread progression. An action allow you to stop all threads.*



## Deployment & Installation

- **SaaS** :

*Cloud support is yet to be finalized*

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
|   Table1_File1.gzip  // Table chunk, row-oriented
|   Table1_File2.gzip  // Table chunk, row-oriented
|   Table2_File1.gzip  // Table chunk, row-oriented
...
|   Table18_File1.colstore.bsc/  // Table chunk, column-oriented
|   |   +-- columns.json         // columns infomrations
|   |   +-- Column_1.bin         // column 1 binary data stream
|   |   +-- Column_2.bin         // column 2 binary data stream
|   |   +-- Column_3.bin         // column 3 binary data stream
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

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/row-vs-column-format.webp?raw=true)


## Column oriented (parquet-like format)

The system automatically use this format when enabled, for tables with >= 100 records.

**Column-oriented is better suited for large table**, it increase compression ratio and improve import speed when some columns are empty or unused.

Each columns are stored as separate binary stream inside a TAR archive. A json file is stored along in the TAR to retrieve columns definition.

When exporting column-orentied data, the program automaticaly detect empty column.

At the export end, empty columns are ignored therefore reducing the file size.

The final TAR file is compressed as one single file, achieving better ratio than row-oriented file, due to better data-pattern groupment.


## Table chunking

A size limit is fixed per file in order to limit RAM usage, and distribute database comits.
When a table export reach the size limit, the file is closedm, compressed and a new stream begin for ongoing record.

Note that using Libbsc compression consume ~5x the file size in RAM (multiplied by threads if concurrent compression).

When importing, comit happen at the end of each chunk. It may happen that a large table is imported by 2+ threads at the same time.


## Optimal binary encoding

Use ZigZag to reduce the size of binary numerical values such as Integer, Decimal, Date ect.

This option offer a small size reduction on final gziped file and also reduce the ram usage when procssing files.

See original repository : [AL-Optimal-Binary-Encoding details](https://github.com/MaximeCaty/AL-Optimal-Binary-Encoding)

**This option is not recommanded when using Libbsc compression**, it lead to increased final file size with uncecessary processing overhead.







