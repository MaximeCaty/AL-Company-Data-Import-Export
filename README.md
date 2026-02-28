# AL Company Data-Import-Export


Remember when we could use this NAV  "Import/Export Data File" top copy company betwen production and test environment ?

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/NavExportData.png?raw=true)

This does not exists anymore in Business Central. 
Only an old powershell command remain and is very unconvenient to use 
(Slow, no visible progression, fail at the first schema difference)

So here is an AL version of Import-Export data file, with offer superior ability than the legacy version.

1. Copy company across different instances (including OnPrem to Cloud or Cloud to OnPrem)
2. Partial company data export/import (you may exclude tables eg logs and archives to fasten the process)
3. Support schema difference with automatic matching suggestion 
4. Error handling - the process continue on next data chunk when an error occur
5. Asissted page for import/export and GUI to follow the process clear progression
6. Optimised for multithreading fast performance
7. Controlled file size using combination of binary encoding, column oriented storage and block-sorting compression

### SaaS Limitations

- Support only gzip compression : lower compression ratio than Libbsc available On-Premise
- Original system fields (Created/Modified/At/By) can not be imported in SaaS
- Performance : cloud import is proceed with AL "Record", significantly slower than On-Premise version using database bulk copy with DLL.

### Export 

Search for the page "Assisted company data export"
Steps :
1. Select the company to export. Estimation of file size and export are calculated.
2. Choose general data export rule : classified data, system fields, global data, logs, archive.
3. Select archive technical data format. Leave "Auto" for the optimal performance/file size ratio.
4. Review the list of tables that will be exported. You can remove table from this list.
5. Review summary, lower the number of threads if you want to reduce server workload, press "Start Export"

![NAV Export Data Form](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Export-Data.png?raw=true)

![NAV Export Data Multi-Threads Progression](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Export-GUI.png?raw=true)

### Import 

Search for the page "Assisted company data import"

1. Upload an archive file. The system read metadata and prepare tables files to import.
2. Select the destination company to import and review Archive file informations.
3. Review the list of table to import and matching status. For each table you can review field matching individualy and adapt the default suggestion.
4. Enable truncate table before importing for a clean import.
5. Review summyarz, lower the number of threads if you want to reduce server workload. press "Start Import"

![NAV Import Data Matching](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Match.png?raw=true)

![NAV Import Data Multi-Threads Progression](https://github.com/MaximeCaty/AL-Company-Data-Import-Export/blob/main/AL-Import-Progress.png?raw=true)

### Deployment

- For SaaS deployment, in app.json remove "ONPREM" pragma :
  ```
  "preprocessorSymbols": [
    "ONPREM"
  ]
  ```
  You can package the app in cloud compatible version then manualy upload it in your instance. 

- For On-Premise deployment : first copy DLLs from .netpackages in your Business Central Addin folder. Restart Business Central instance. Then publish the app.
- Recommanded : To get **much better compression**, copy bsc.exe in the addin folder. This executable can be found here [GitHub Libbsc release](https://github.com/IlyaGrebnov/libbsc/releases/tag/v3.3.12)

### Archive Format 

```
Archive.zip/
|   datameta.json      // tables schema and files info.
|   Table1_File1.bsc   // Table chunk, row-oriented binary 
|   Table1_File2.bsc   // Table chunk, row-oriented binary
|   Table2_File1.bsc   // Table chunk, row-oriented binary
...
|   Table_File3.colstore.bsc/   // Table chunk, column-oriented TAR file
|   |   +-- metadata.json       // field-column file info.
|   |   +-- Column_1.bin        // table column binary data
|   |   +-- Column_2.bin
...
```

**How data is encoded**
- Row-oriented

The system automatically use this format for tables with < 100 records.

Row-oriented is better suited for small table because it does not have the column managment overhead.

Each table record is written as a "row" composed of all the field binary values.

The file does not contain any metadata, separators or control character.

- Column oriented (parquet-like format)

The system automatically use this format for tables with >= 100 records.

Column-oriented is better suited for large table, because it increase compression and improve import speed when there is empty columns.

Each column is a separate binary stream that are stored in a TAR archive, along with a .json storing connections of column file-table field.

When the process end, any columns without any value are skipped and not written in the archive.

The final full TAR archive is compressed as a single file, achieving better ratio than row-oriented file.

- Table chunking

A size limit is fixed per file in order to limit maximal RAM usage, and distribute database comits.

When the in memory export file reach the limit, it is closed, compressed then stored and a new file start for the ongoing table records.

- Optimal binary encoding

This option reduce the number of bytes needed to write numericals. This reduce the average RAM usage during import/export and final file size when using Gzip compression.
See original repository : [AL-Optimal-Binary-Encoding details](https://github.com/MaximeCaty/AL-Optimal-Binary-Encoding)

This option is not recommanded when using block sorting compression because it may degrade compression ratio with no other significant gain.


* Compression
    * Auto (On-Premise) : Use zStd for small file up to 1 MB, then Libbsc for larger file. Max. file chunk is 150 MB. Optimal binary encoding is disabled. System fields included.
    * Auto (SaaS) : Use Gzip. Max. file chunk is 200 MB. Optimal binary encoding is enabled. System fields skiped.
    * Gzip : Use gzip at "optimal" level
    * zStd : use zStandard at medium level (12/22)
    * Libbsc : Use block sorting compression at maximum level (2/2)







