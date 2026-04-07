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

|                               | Cronus W1 23.18    | Company with 1Y intensive activities |
|-------------------------------|--------------------|--------------------------------------|
| Database MDF disk size        | 1 GB               | 45 GB           |
| Tables with data              | 548                | 365             |
| Number of records             | 43'783             | 8'662'740       |
| Export Duration               | **5.5 s**          | **12 minutes**  |
| Export file size compressed   | **3.5 MB**         | **357 MB**      |
| Import Duration (OnPrem .NET) | **8.3 s**          | **17 minutes**  |
| Import Duration (Cloud)       | 10.5 s             | 53 minutes      |


### OnPrem vs SaaS Limitations

Saas usage as some tradeoff regarding OnPrem :

|                               | SaaS               | On-Premise                           |
|-------------------------------|--------------------|--------------------------------------|
| Exported File size            |  ~35% larger : Gzip | zStd + libbsc compressors           |
| Speed                         | Native AL          | SQL bulk via DLL, ~2.5x faster on large table  |
| System fields (Created/Modified/At/By) | Original value lost | Original value imported via direct SQL |

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

Download .APP from the repository Release folder. Additional DLL for OnPremise can also be found in the zip.


### On-Premise 
1. Enable write inside TryFunction on the Business Central instance : ```SetNavServer-Configuration Instance -KeyName DisableWriteInsideTryFunctions -KeyValue false```
2. BC 27+ : to enable SQL DLL import, and advanced compressor : ```SetNavServer-Configuration Instance -KeyNam EnforceUserPathForAlFileOperations -KeyValue false```
4. Copy DLLs from ```.netpackages``` in Business Central ```Service/Addin``` folder
5. Restart Business Central instance service 
6. Publish the app

- **❗Recommanded :** for smaller export file size, use block sorting compressor : Put bsc.exe in Business Central Addin folder, the app use it to further reduce file size when available.
The executable can be found in Ilya repository : [GitHub Libbsc release](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12) 


### Cloud 

Upload the .APP from the release folder - SaaS version

Or compile from the source code :

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

| Mode              | Algorithm             | Best for             |  Column Oriented storage | Max Table-Chunk Size | Include System fields |
|-------------------|-----------------------|----------------------|----------------------|----------------------|----------------------|
| Auto (On-Premise) | zStd (<1Mb) → libbsc  | Speed + Compression  | ✅                  | 75 MB                | ✅                  |
| Auto (SaaS)       | Gzip 6/9              | Cloud compatibility  | ✅                  | 200 MB               | ❌                  |
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

The data is written in binary format, allowing faster parsing and smaller files than text based data such as CSV. 

**Binaries streams only contain table data**, without any headers or separators. 

 - Row-oriented — used for small tables (< 100 rows); simple and low-overhead.
 - Column-oriented — used for larger tables (≥ 100 rows); better compression ratio, faster imports, skipping empty columns to further reduce size (detected based on BC default values comparisons)
   - Compressed TAR archive, containing each column as separate stream + json with columns definitions
 - MD5 hash verification after each file decompressed to ensure integrity

![NAV Import Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/row-vs-column-format.webp?raw=true)
 
### Table chunking

A size limit is fixed per file in order to limit RAM usage, and distribute database comits.  
When a stream reach the size limit, the file is closed, compressed and a new stream begin for ongoing records.  
Note that using Libbsc compression require much free RAM : ~5x the file size, multiplied by threads.  
When importing, comit happen at the end of each chunk. It may happen that a large table is imported by 2+ threads at the same time.





