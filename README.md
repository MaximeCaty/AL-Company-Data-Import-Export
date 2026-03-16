
# AL Company Data-Import-Export

Offer Business Central replacement for legacy NAV "Import / Export Data File" that does not exists anymore.
Use this app to copy a company across different instances, without replacing the whole database.

| Feature                  | Legacy NAV | This extension                  |
|--------------------------|------------|---------------------------------|
| Partial table selection  | ❌ per scope          | ✅ per table                               |
| Schema mismatch handling | ❌ fail on first schema difference         | ✅ Auto-match + manual control   |
| UI Visibility            | ❌ freeze         | ✅ Assisted setup + Per-thread progression |
| Error recovery           | ❌ full rollback | ✅ Log and continues to next chunk    |
| Multithreaded processing | ❌          | ✅                               |
| Tight file size          | ❌ basic compression | ✅ Column-oriented + zStd/libbsc |


### OnPrem vs SaaS Limitations

ℹ️ SaaS support is almost functionnal but not finalized. See Deployment. We use "Table Information" to get real data size but this table have scope = OnPrem.

Addtionnaly there would be bellow limitations :

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


-  **On-Premise** : 
1. Copy DLLs from ```.netpackages``` in your Business Central Addin folder. 
2. Restart Business Central instance. 
3. Then publish the app with the "ONPREM" pragma

- **❗Recommanded for better compression :** to use block sorting compression, copy bsc.exe into Busienss Central Addin folder. The app will automatically use it to further reduce file size.
This executable can be found here [GitHub Libbsc release](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12) 


- **SaaS** :

*Cloud support is yet to be finalized*

in ```app.json``` remove "ONPREM" pragma :
  ```
  "preprocessorSymbols": [
    "ONPREM"
  ]
  ```
  "Table Information" OnPrem scope need to be solved to publish it on SaaS
  

## Archive File Format & Encoding

This chapter explain how the data is structured inside archive files.

### Options offered in the assisted export

| Mode              | Algorithm             | Best for             |  Column Oriented storage | Optimal binary encoding | Include System fields |
|-------------------|-----------------------|----------------------|----------------------|----------------------|----------------------|
| Auto (On-Premise) | zStd (<1Mb) → libbsc  | Speed + Compression  | ✅                  | ❌                   | ✅                  |
| Auto (SaaS)       | Gzip 6/9              | Cloud compatibility  | ✅                  | ✅                   | ❌                  |
| Gzip              | Gzip 6/9              | Universal            | Manual               | Manual               | Manual               |
| zStd              | zStandard level 12/22 | Best Speed/Ratio     | Manual               | Manual               | Manual               |
| Libbsc            | bsc.exe level 1/2     | Heavy compression    | Manual               | Manual               | Manual               |



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

All business central data are written in binary format, allowing faster parsing and smaller files than text based data such as CSV. 

**Binaries streams only contain table data**, without any headers or separators. 

 - Row-oriented — used for small tables (< 100 rows); simple and low-overhead, sequencial per record then per field loop.
 - Column-oriented — used for large tables (≥ 100 rows); better compression ratio and faster imports; empty columns automatically skipped (detected based on BC default values)
   - Compressed TAR archive, containing each column as separate stream + json with columns definitions
 - MD5 hash verification after each file decompressed to ensure integrity

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/row-vs-column-format.webp?raw=true)
 
### Table chunking

A size limit is fixed per file in order to limit RAM usage, and distribute database comits.
When a stream reach the size limit, the file is closed, compressed and a new stream begin for ongoing records.

Note that using Libbsc compression require much free RAM : ~5x the file size, multiplied by threads.

When importing, comit happen at the end of each chunk. It may happen that a large table is imported by 2+ threads at the same time.


### Optimal binary encoding

Uses ZigZag encoding to shrink numerical types (Integer, Decimal, Date, etc.). Reduces file size and RAM usage during processing.

This option offer help reduce final gziped file, and also reduce ram consumption during import/export.

See original repository : [AL-Optimal-Binary-Encoding details](https://github.com/MaximeCaty/AL-Optimal-Binary-Encoding)

*⚠️ Not recommended when using libbsc — the block-sorting compressor is more effective on unencoded binary data, and may lead to increased file size.*







