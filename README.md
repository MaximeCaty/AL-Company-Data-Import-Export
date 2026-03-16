
# AL Company Data-Import-Export


Remember when we could use this NAV  "Import/Export Data File" top copy company betwen production and test environment ?

![Legacy Company Data Import Export](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/NavExportData.png?raw=true)

This does not exists anymore in Business Central. 
Only an old powershell command remain and is very unconvenient to use 
(Slow, no visible progression, fail at the first schema difference)

| Feature                  | Legacy NAV | This extension                  |
|--------------------------|------------|---------------------------------|
| Partial table selection  | ❌          | ✅                               |
| Schema mismatch handling | ❌          | ✅ Auto-match + manual control   |
| Progress visibility      | ❌          | ✅ Per-thread live progress      |
| Error recovery           | ❌          | ✅ Continues on chunk failure    |
| Multithreaded processing | ❌          | ✅                               |
| Compressed binary format | ❌          | ✅ Column-oriented + zStd/libbsc |

So here is an AL version of Import-Export data file, with offer superior ability than the legacy version.

2. **Partial company data** selection possible for export/import (you may exclude tables like logs to limit data size)
3. **Support schema difference** at import : auto suggest table and field matching with manual control
4. **Assisted page** for import/export with GUI process progression
5. **Error handling** : the process continue on next data chunk when an error occur
6. **Optimised performance** with multithreading
8. **Restricted file size** using combination of binary encoding, column oriented storage and advanced compression


### Usage SaaS vs On-Premise Limitations

*ℹ️ SaaS support is functional but not yet finalized. See Deployment for how to strip the ONPREM pragma. We use "Table Information" to get real data size insight, this table have scope = OnPrem. Feel free to adapt the code if you like to use it on Cloud.*

|                               | SaaS               | On-Premise                           |
|-------------------------------|--------------------|--------------------------------------|
| Compression                   | Gzip               | zStd / libbsc (~40% smaller)         |
| Insert performance            | Native AL (slower) | SQL bulk insert via DLL (~3× faster) |
| System fields (Created At/By) | ❌ Cannot import    | ✅ Imported via direct SQL            |
| Table size insight            | ❌ Limited          | ✅ Full (Table Information)           |

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

- **❗Recommanded for better compression :** to use block sorting compression, copy bsc.exe into Busienss Central Addin folder. The app will automatically use it to further reduce file size.
This executable can be found here [GitHub Libbsc release](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12) 



## Archive File Format & Encoding

This chapter explain how the data is structured inside archive files.

### Options offered in the assisted export

| Mode              | Algorithm             | Best for             | Optimal binary encoding | Include System fields |
|-------------------|-----------------------|----------------------|----------------------|----------------------|
| Auto (On-Premise) | zStd (<1Mb) → libbsc  | Speed + Compression  | ❌                   | ✅                  |
| Auto (SaaS)       | Gzip 6/9              | Cloud compatibility  | ✅                   | ❌                  |
| Gzip              | Gzip 6/9              | Universal            | Manual               | Manual               |
| zStd              | zStandard level 12/22 | Best Speed/Ratio     | Manual               | Manual               |
| Libbsc            | bsc.exe level 1/2     | Higher compression   | Manual               | Manual               |



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

 - Row-oriented — used for small tables (< 100 rows); simple and low-overhead
 - Column-oriented — used for large tables (≥ 100 rows); better compression ratio and faster imports; empty columns are automatically skipped (detected based on BC default values)
   - Compressed TAR archive, containing each column as separate binary streams + json with columns definitions
 - MD5 hash verification after each decompressed file to ensure integrity

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/row-vs-column-format.webp?raw=true)
 
### Table chunking

A size limit is fixed per file in order to limit RAM usage, and distribute database comits.
When a table export reach the size limit, the file is closedm, compressed and a new stream begin for ongoing record.

Note that using Libbsc compression consume ~5x the file size in RAM (multiplied by threads if concurrent compression).

When importing, comit happen at the end of each chunk. It may happen that a large table is imported by 2+ threads at the same time.


### Optimal binary encoding

Uses ZigZag encoding to shrink numerical types (Integer, Decimal, Date, etc.). Reduces file size and RAM usage during processing.

This option offer a size reduction on final gziped file and also reduce the ram usage when procssing files.

See original repository : [AL-Optimal-Binary-Encoding details](https://github.com/MaximeCaty/AL-Optimal-Binary-Encoding)

*⚠️ Not recommended when using libbsc — the block-sorting compressor is more effective on unencoded binary data, and may lead to increase of file size.*







