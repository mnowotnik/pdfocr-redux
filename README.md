# pdfocr.sh

A convenience script that implements a pipeline for creating a searchable
pdf file. The pipeline involves three parts:
  - pdf splitting and conversion to images
  - user-defined image preprocessing
  - character recognition
  - merging into the final pdf

Each step can be performed separately of others. You can split pdf, preprocess
images (e.g. with ImageMagick) and then perform ocr and merging.

## Requirements:

  The following software applications are required:
  - gs (Ghostscript)
  - tesseract
  - pdfunite

#### Optional dependencies:
  - parallel (speeds up ocr on multiple cores)

## Usage:

    pdfocr -i|--input input.pdf [options...]

## Options:

    -l, --lang LANGS            set the language(s) for tesseract; check available
                                languages with: 
                                    tesseract --list-langs

    -o, --output OUTPUT_PATH  set the output path; it can be explicit or use the
                                INPUT_BASENAME variable to construct it dynamically
                                e.g. , -o INPUT_BASENAME_ocr.pdf
                                Default: INPUT_BASENAME_ocr.pdf

    -t, --tempdir TMPDIR_PATH set the path to directory with intermediate
                                files; Default: ~/tmp

    -s, --preprocessor PROC_PATH set the path to an image preprocessor;
                                the preprocessor shall be executed for the image of
                                each page like this:
                                    preprocessor img_path page_num
                                the preprocessor should overwrite the original image

    -m, --mode MODE           set the mode to perform only the part of processing;
                                MODE can be one of: 
                                split
                                ocr
                                merge
                                full  
                                Default: full
                                note: it is assumed that required files are in the
                                TMPDIR_PATH; modes 'split' and 'ocr' don't delete
                                their output intermediate files

    -c, --tess-config         set the tesseract configuration; default: pdf

    -p, --parallel [JOBS]     use GNU parallel if available; limit the number
                                of jobs to JOBS

        --keep-tmp            keep the intermediate files; deleted by default

    -f, --img-format          the format of the intermediate images; 
                                possible values:
                                jpeg png* ppm tiff*
                                any format supported by Ghostscript that matches
                                the above values is valid;
                                notice: the image format makes a difference for
                                tesseract, so experiment with different values
                                Default: jpeg

    -r, --resolution          set the resolution of the intermediate images;
                                default: 300

        --tess-params         set the tesseract parameters; those should be inside
                                double quotes e.g., "-c textord_min_linesize=2.5"

    -h, --help                print this

