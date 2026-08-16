.App can be found under [release folder here.](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/releases)  
If you're happy with it and on-prem, git a try to the on-prem+dll version that offer faster import and better compression.

# AL Company Data-Import-Export

Offer Business Central replacement for legacy NAV "Import / Export Data File".  
Use this app to copy a company across different instances, without replacing the whole database, or migrate schema differences.

| Feature                  | Legacy NAV | This extension                  |
|--------------------------|------------|---------------------------------|
| Multiple Company Imp/Exp | ✅         | ❌ One company at a time       |
| Data selection  | ❌ all + choose globale Y/N | ✅ per table        |
| Schema mismatch handling | ❌ fail on first schema difference         | ✅ Auto-match + manual control   |
| UI Visibility            | ❌ freeze         | ✅ Assisted setup + threads progression |
| Error recovery           | ❌ full rollback | ✅ Log and continues to next chunk    |
| Multithreaded processing | ❌          | ✅                               |
| Tight file size          | ❌ basic compression | ✅ Column-oriented storage + zStd/libbsc |

### Performance Sample

| Comparison v1.0.0.4 / v2.0.0.0<br>(4 threads - auto - no system fields)     | Cronus W1 BC230           | Misc company                    |
|-----------------------------------------------------------------------------|---------------------------|---------------------------------|
| Database MDF disk size                                                      | 1 GB                      | 45 GB                           |
| Tables with data                                                            | 548                       | 365                             |
| Number of records                                                           | 43'783                    | 8'662'740                       |
| Export Duration (Cloud Format)                                              | 4.4 s / 4.1 s (-6%)       | 12 minutes / 6 minutes (-50 %)  |
| Exported Archive size (GZip)                                                | 3.5 MB / 3.2 MB (-8%)     | 357 MB / 252 MB (-30%)          |
| Exported Archive size (OnPrem Max Compression)                              |  -        / 2.8 MB (-20%) |  -         / 220 MB (-43%)      |
| Import Duration                                                             | 9.3 s / 7.8 s (-16%)      | 53 minutes / 49 minutes (-7.5%) |
| Import Duration (OnPrem SQL DLL)                                            | 8.3 s / 7.0 s (-15%)      | 17 minutes / 14 minutes (-17%)  |


### OnPrem vs SaaS Limitations

Saas usage as some tradeoff regarding OnPrem :

|                               | SaaS               | On-Premise                           |
|-------------------------------|--------------------|--------------------------------------|
| Exported File size            |  ~35% larger : Gzip | zStd + libbsc compressors           |
| Speed                         | Native AL          | SQL bulk via DLL, ~3x faster on large table  |
| System fields (Created/Modified/At/By) | Original value lost | Original value imported via SQL |

## Export 

Search for the page "Assisted company data export" :

Steps :
1. Select the company to export
2. Choose data scope : classified data, system fields, include global data / logs / archive
4. Archive data format ("Auto" by default)
5. Review the list of tables included in export. You may remove table manualy from the list.
6. Review summary. Recommanded to use max 2 threads when the instance is in use, to avoid performance impact on users while exporting.

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Export-UI.png?raw=true)


## Import 

Create a new blank company first.

Then search for the page "Assisted company data import"

1. Upload an archive, the system read metadata and prepare import
2. Select destination company
3. Review the list of table to import and matching
4. Review summary. Recommanded to use max 2 threads when the instance is in use, to avoid performance impact on users while importing.

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Match.png?raw=true)

*You can change table mapping manually at this step with the column "Matched Table ID". Drill down on the "No. fields" column to change a table field mapping details when needed.*
 - *"⚠️ Partial" mean that some fields are not mapped to the destination table.*
 - *"⛔ Missing" mean that the table is not mapped to a destination table.*

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Progress-Page.png?raw=true)

*Import progress can be either show on a foreground dialog or with this separated page, showing each thread progression. An action allow you to stop all threads.*



## Deployment & Installation

Download .APP from the repository Release folder. Additional DLL for OnPremise can also be found in the zip.


### On-Premise 
1. Enable write inside TryFunction on the Business Central instance : ```SetNavServer-Configuration Instance -KeyName DisableWriteInsideTryFunctions -KeyValue false```
2. BC 27+ : to enable SQL DLL import, and advanced compressor : ```SetNavServer-Configuration Instance -KeyNam EnforceUserPathForAlFileOperations -KeyValue false```
4. Copy DLLs from ```.netpackages``` in Business Central ```Service/Addin``` folder
5. Restart Business Central instance service 
6. Publish the app

- **❗Recommanded :** for smaller archive file, use frontier compressor programs, put bsc.exe and kanzi.exe in Business Central Addin folder. The app will use it when available.
<br>Both executable are available in the zip. 
<br>Original libbsc.exe repository : [GitHub Libbsc release, by Ilya Grebnov](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12) 
<br>Original kanzi.exe repository : [GitHub Kanzi-Cpp, By Frederic Langlet](https://github.com/flanglet/kanzi-cpp) 


### Cloud 

Upload the .APP from the release folder - SaaS version

Or compile it yourself from the source code :

1. Simply remove the preprocessorSymbols in ```app.json``` :
  ```
  "preprocessorSymbols": [
    "ONPREM"  <- Remove this
  ]
  ```
2. Change the target to cloud : ```"target": "Cloud",```

Thats it! The extension compile for SaaS.
  

## Archive File Format & Encoding

This chapter explain how the data is structured inside archive files.

### Options offered in the assisted export

| **Mode**          | **Algorithm**         | **Best for**        | **Column Oriented storage** | **Dictionnaries** | **Max Table-Chunk Size** | **Include System fields** |
|-------------------|-----------------------|---------------------|-----------------------------|-------------------|--------------------------|---------------------------|
| Auto (On-Premise) | zStd → libbsc → kanzi*| Speed + Compression | ✅                           | ✅                 | 75 MB                    | ✅                     |
| Auto (SaaS)       | Gzip 6/9              | Cloud compatibility | ✅                           | ✅                 | 200 MB                   | ❌                     |
| Gzip              | Gzip 6/9              | Universal           | Manual                       | Manual              | Manual                   | Manual                 |
| zStd              | zStandard level 12/22 | Best Speed/Ratio    | Manual                       | Manual              | Manual                   | Manual                 |
| Libbsc            | bsc.exe level 1/2     | High compression    | Manual                       | Manual              | Manual                   | Manual                 |
| Kanzi TPAQ        | kanzi.exe TPAQ        | Extreme compression | Manual                       | Manual              | Manual                   | Manual                 |
* Auto (On-Premise) : use zstandard on small file (< 256 KB) then libbsc or kanzi for larger file. Depend the compression level choosen in the export assistant.


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
|   dict/
|   |   optionset.bin           // store the index of all options ordinal, for options/enum that have <= 256 values
|   |   Vendor$No.bin            // store single byte index of each vendor "No." field when there is less than 254 different possible values
```


### How data is encoded

The data is written in binary format, allowing faster parsing and smaller files than text based data such as CSV. 
Binaries streams only contain table raw data, without any headers or separators. 

 - Row-oriented — used for small tables (< 100 rows); simple and low-overhead.
 - Column-oriented — used for larger tables (≥ 100 rows); better compression ratio, faster imports, skipping empty columns to further reduce size (detected based on BC default values comparisons)
   - Compressed TAR archive, containing each column as separate stream + json with columns definitions
 - MD5 hash verification after each file decompressed to ensure integrity

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/row-vs-column-format.webp?raw=true)

### Dictionnaries

To reduce files sizes, and fasten file reading & witting, the system detect fields that can use a single byte index instead of litteral values.
Compression algorithm are doing great at reducing redundant values, but when a field has a list of fixed values referenced many time/in many tables, it is more efficient to write the fixed list only once.

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/dict-encoding.png?raw=true)

The system detect candidat based on :
 - Option/Enum fields : whenever the option has less than 256 possibles ordinals (almost all) : replace the AL 4 bytes ordinal by a single byte index. Index to ordinal mapping are stored in "optionset.bin" (usualy ~1 KB).
 - Text/Code fields : when they have table relation in other table (foreign key), and when there is <= 254 possible values, and the foreign table contain at least >= 1.86x the parent table to make the dictionnary worth building (eg : there is 100 vendors and 500 vendor ledger entries that contain vendor "No." field).

### Table chunking

A size limit is fixed per file in order to limit RAM usage while reading/writting, and distribute database comits on import.  
When a stream reach the size limit, the file is closed, compressed and a new stream begin for ongoing records.  

Note that using Libbsc or kanzi compression require much free RAM, somehwere about ~5x the file size, multiplied by threads. 
When importing, comit happen at the end of each chunk. It may happen that a large table is imported by 2+ threads at the same time.





