controladdin "TOO ChunkedFileUploader"
{
    MinimumHeight = 180;
    MinimumWidth = 380;
    RequestedHeight = 180;
    RequestedWidth = 380;
    StartupScript = 'src/AddinUploader/uploader.js';
    StyleSheets = 'src/AddinUploader/uploader.css';

    // Événements déclenchés par JS
    event StartUpload(UploadedFileName: Text; TotalSize: Integer);
    event UploadChunk(BinaryTextChunk: BigText; ChunkNumber: Integer);
    event FinishUpload();
    event UploadError(ErrorMessage: Text);
}