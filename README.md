# PDFOCR-Redux
![zoom](img/magni-glass.png)

Your typical pdfocr bash script revisited! All the flexibility and speed is
already here. Not to mention new handy features to blow your socks off. 

PDFOCR implements a pipeline for creating a searchable
pdf file. The pipeline involves four parts:
  - pdf splitting and conversion to images
  - user-defined image preprocessing
  - character recognition
  - merging into the final pdf

Each step can be performed separately of others. You can split pdf, preprocess
images (e.g. with ImageMagick) and then perform ocr and merging.

## Usage

    pdfocr -i input.pdf [options...]

## Motivation

Available pdfocr scripts are neat, but I needed speed and flexiblity in
dealing with tessaract. So I decided to roll my own. 

This pipeline tries to be as transparent as possible so it's very easy to
modify the script and add new stages. Just check the [source](pdfocr.sh).

Moreover, with the optional preprocessor component, it can be used as
all-purpose ocr script, not just for creating searchable pdfs.

## Requirements

  The following software applications are required:
  - gs (Ghostscript)
  - gawk
  - tesseract
  - pdfunite

#### Optional dependencies
  - parallel (speeds up ocr and preprocessing on multiple cores)


## Examples

    pdfocr -i *.pdf -o mydir/ -t /path/tempdir -p 2 -l eng de 

  run pdfocr.sh on every .pdf file in the working directory,
  created pdf files put in the mydir directory and create it if doesn't exist.
  During ocr process use 2 cores. Use tempdir for temporary files.
  Instruct tessaract to look for English and German languages in the pdfs.

    pdfocr -i d/input1.pdf d/input2.pdf -s remove_lines.py

  run pdfocr.sh on input1.pdf and input2.pdf. Put the output in the 'd'
  directory. Run remove_lines.py preprocessor on every image.

    pdfocr -i in.pdf -o INPUT_BASENAME_new.pdf -p

  run pdfocr.sh on in.pdf and name the output file as in_new.pdf.
  Use all available cores.


## Options:

    -l, --lang LANGS            set the language(s) for tesseract; check available
                                languages with: 
                                    tesseract --list-langs

    -o, --output OUTPUT_PATH    set the output path; it can be explicit or use
                                the INPUT_BASENAME variable to construct it
                                dynamically e.g. , -o INPUT_BASENAME_ocr.pdf
                                Default: INPUT_BASENAME_ocr.pdf

    -t, --tempdir TMPDIR_PATH   set the path to directory with intermediate
                                files; Default: ~/tmp

    -s, --preprocessor PROC_PATH set the path to an image preprocessor;
                                the preprocessor shall be executed for the
                                image of each page like this:
                                    preprocessor img_path page_num
                                the preprocessor should overwrite the original
                                image

    -m, --mode MODE             set the mode to perform only the part of
                                processing;
                                MODE can be one of: 
                                    split
                                    ocr
                                    merge
                                    full  
                                    clean
                                Default: full
                                note: it is assumed that required files are in
                                the TMPDIR_PATH; modes 'split' and 'ocr' don't
                                delete their output intermediate files

        --tess-config           set the tesseract configuration; default: pdf

    -p, --parallel [JOBS]       use GNU parallel if available; limit the number
                                of jobs to JOBS

    -v, --verbose               allow verbose output

        --keep-tmp              keep the intermediate files; deleted by default

    -f, --img-format            the format of the intermediate images; 
                                possible values:
                                jpeg png* ppm tiff*
                                any format supported by Ghostscript that matches
                                the above values is valid;
                                note: the image format makes a difference for
                                tesseract, so experiment with different values
                                Default: jpeg

    -r, --resolution RES        set the resolution of the intermediate images;
                                Default: 300

    -c, --tess-param key=val    set a tesseract parameter
                                e.g., -c textord_min_linesize=2.5

    -h, --help                  print this
    
