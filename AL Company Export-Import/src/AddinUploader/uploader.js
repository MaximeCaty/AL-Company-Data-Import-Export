const textDecoder = new TextDecoder('iso-8859-1');  // Latin-1 = 1 octet = 1 char

function arrayBufferToBinaryText(buffer) {
    return textDecoder.decode(buffer, { stream: true });
}

// Fonction principale pour uploader le fichier en chunks
function uploadFileInChunks(file, chunkSize = 1024 * 1024 * 2) {  // default chunk size (2 MB)
    const totalSize = file.size;
    const fileName = file.name;
    let offset = 0;
    let chunkNumber = 0;

    // Déclencher l'événement de démarrage en AL de manière asynchrone
    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('StartUpload', [fileName, totalSize], false, () => {
        // Succès : démarrer la lecture des chunks
        readNextChunk();
    }, (error) => {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('UploadError', [error]);
    });

    const readNextChunk = () => {
        if (offset < totalSize) {
            const chunk = file.slice(offset, offset + chunkSize);
            const reader = new FileReader();
            reader.onload = (e) => {
                const binaryText = arrayBufferToBinaryText(e.target.result);
                // Send chunk to AL asynchronously
                Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('UploadChunk', [binaryText, chunkNumber], false, () => {
                    // Sucess : go to next chunk
                    chunkNumber++;
                    offset += chunkSize;
                    readNextChunk();
                }, (error) => {
                    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('UploadError', [error]);
                });
            };
            reader.onerror = (e) => {
                Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('UploadError', [e.target.error]);
            };
            reader.readAsArrayBuffer(chunk);
        } else {
            // End of chunks : trigger the finish upload AL function
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('FinishUpload', [], false, () => {
                // Optionnel : notifier la fin complète si besoin
                console.log('File Upload finished sucessfully');
            }, (error) => {
                Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('UploadError', [error]);
            });
        }
    };
}

// Fonction d'initialisation (appelée au startup, ex: dans startup.js)
function initUploader() {

    var addin = document.getElementById('controlAddIn');

    addin.innerHTML = '<label for="images" class="drop-container card" id="dropcontainer">Upload-Max<span class="drop-title">Drop a file here</span><input type="file" id="uploadFile"><span id="status"></span></label>';
  
    // Styling
    const dropContainer = document.getElementById("dropcontainer")
    const fileInput = document.getElementById("uploadFile")


    dropContainer.addEventListener("dragover", (e) => {
      // prevent default to allow drop
      e.preventDefault()
    }, false)

    dropContainer.addEventListener("dragenter", () => {
      dropContainer.classList.add("drag-active")
    })

    dropContainer.addEventListener("dragleave", () => {
      dropContainer.classList.remove("drag-active")
    })

    dropContainer.addEventListener("drop", (e) => {
        e.preventDefault()
        dropContainer.classList.remove("drag-active")
        let files = e.dataTransfer.files;
        if (files.length == 1) {
            uploadFileInChunks(files[0]);
        }
    })

    var input = document.getElementById('uploadFile');
    input.addEventListener("change", async (e) => {  
        let file = e.target.files[0];
        if (file) {
            uploadFileInChunks(file);
        }
    });
}

// Appel initial (dans startup.js ou directement)
initUploader();