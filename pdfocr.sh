#! /bin/bash

INPUT=
OUTPUT=
TESS_CONFIG=pdf
TESS_LANG=eng
RES=300
IMG_FMT=
MODE=full
TESS_PARAMS=
KEEP_TMP=false
MODE=full
PARALLEL=false
GSDEV=jpeg
INPUT_BASENAME=
TMPDIR_PATH=~/tmp

function pdfocr {

  if [ $# -eq 0 ]; then
    print_usage
    exit
  fi

  parse_args $*

  check_req

  init

  if [[ $MODE = @(full|split) ]];then
    echo Running ghostscript on $INPUT

    gs -dSAFER -dBATCH -dNOPAUSE -sDEVICE=$GSDEV -r$RES -dTextAlphaBits=4 \
      -o "$TMPDIR_PATH/$INPUT_BASENAME%04d_gs.$IMG_FMT" -f "$INPUT" > /dev/null

   try "Error while converting $INPUT"
   exit_on_mode $MODE
  fi

  if [[ $MODE = @(full|ocr) ]]; then

    local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"*_gs.$IMG_FMT
    if [ $PARALLEL = true ]; then
      echo Running tesseract on multiple cores
      export -f run_tess
      export TESS_PARAMS
      export TESS_LANG
      export TESS_CONFIG
      parallel run_tess ::: $IN_P
      try "Error while performing ocr"
    else
      for f in $IN_P; do
        echo Running tesseract
        run_tess "$f"
        try "Error while performing ocr"
        echo input $f 
        echo output ${f%.*}_tess.pdf
      done
    fi


   exit_on_mode $MODE
  fi

  if [[ $MODE = @(full|merge) ]]; then
    echo merging into $OUTPUT
    pdfunite "$TMPDIR_PATH/$INPUT_BASENAME"*_gs_tess.pdf $OUTPUT 
    try "Error while merging "$TMPDIR_PATH/$INPUT_BASENAME"*_gs_tess.pdf into $OUTPUT"
  fi

  if [ $KEEP_TMP = false ]; then

    if [ $MODE != split ]; then
      rm "$TMPDIR_PATH/$INPUT_BASENAME"*_gs.$IMG_FMT
    fi
    if [ $MODE != ocr ]; then
      rm "$TMPDIR_PATH/$INPUT_BASENAME"*_gs_tess.pdf
    fi

  fi

  echo Finished

}

function run_tess {
    tesseract "$1" "${1%.*}_tess" -l $TESS_LANG -psm 3 $TESS_PARAMS $TESS_CONFIG
}

function exit_on_mode {

  if [[ $1 = @(split|ocr) ]];then
    echo Finished
    exit
  fi

}

function init {

  INPUT_BASENAME=$(basename "$INPUT")
  INPUT_BASENAME=${INPUT_BASENAME%.*}

  if [ -z "$OUTPUT" ]; then

    local INPUT_DIR=$(dirname "$INPUT")
    OUTPUT="$INPUT_DIR/$INPUT_BASENAME"_ocr.pdf

  else

    if [[ $OUTPUT =~ *INPUT_BASENAME* ]]; then
      OUTPUT=${$OUTPUT/INPUT_BASENAME/$INPUT_BASENAME}
    fi

    local OUTPUT_DIR=$(dirname $OUTPUT)
    if [ ! -d "$OUTPUT_DIR" ]; then
      mkdir -p "$OUTPUT_DIR"
      try "Failed creating the output directory: $OUTPUT_DIR"
    fi

  fi

  if [ ! -d "TMPDIR_PATH" ]; then
    mkdir -p "$TMPDIR_PATH"
    try "Failed creating the temporaroy directory: $TMPDIR_PATH"
  fi

  case $GSDEV in
  jpeg)
    IMG_FMT=jpg
    ;;
  ppm)
    ;;
  png*)
    IMG_FMT=png
    ;;
  tiff*)
    IMG_FMT=tiff
    ;;
  *)
    echo $IMG_FMT not supported
    exit
    ;;
  esac
}

function parse_args {

  while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -i|--input)
      INPUT="$2"
      shift
      ;;
    -o|--output)
      OUTPUT="$2"
      shift
      ;;
    -t|--tempdir)
      TMPDIR_PATH="$2"
      shift
      ;;
    -tess-config|-c)
      TESS_CONFIG="$2"
      shift
      ;;
    -l|--language)
      TESS_LANG="$2"
      shift
      ;;
    -r|--resolution)
      RES="$2"
      shift
      ;;
    -f|--img-format)
      GSDEV="$2"
      shift
      ;;
    --tess-params)
      TESS_PARAMS="$2"
      shift
      ;;
    --keep-tmp)
      KEEP_TMP=true
      shift
      ;;
    -m|--mode)
      MODE="$2"
      shift
      ;;
    -p|--parallel)
      if which parallel >/dev/null; then
        PARALLEL=true
      fi
      shift
      ;;
    -h|--help)
      print_help
      exit
      ;;
    esac
    shift
  done

}

function check_req {

  if ! which pdfunite > /dev/null; then
    echo pdfunite missing!
    exit
  fi

  if ! which tesseract > /dev/null; then
    echo tesseract missing!
    exit
  fi

  if ! which gs > /dev/null; then
    echo ghostscript missing!
    exit
  fi

  if [ -z "$INPUT" ]; then
    echo pdf input path is missing!
    exit
  fi
}

function try {

  if [ $? -ne 0 ] ; then
    echo $1
    exit
  fi
}

function print_help {

  cat << END
pdfocr script

Description:

  A convenience script that implements a pipeline for creating a searchable
pdf file. The pipeline involves three parts:
  -pdf splitting and conversion to images
  -character recognition
  -merging into the final pdf
Each step can be performed separately of others. You can split pdf, preprocess
images (e.g. with ImageMagick) and then perform ocr and merging.

Requirements:

  The following software applications are required:
  gs (Ghostscript)
  tesseract
  pdfunite

  Optional:
    parallel (speeds up ocr on multiple cores)

Usage:

  pdfocr -i|--input input.pdf [options...]

Options:

  -l, --lang "LANG"         set the language(s) for tesseract; check available
                            languages with: tesseract --list-langs; put multiple
                            languages inside double quotes

  -o, --output OUTPUT_PATH  set the output path; it can be explicit or use the
                            INPUT_BASENAME variable to construct it dynamically
                            e.g. , -o INPUT_BASENAME_ocr.pdf
                            Default: INPUT_BASENAME_ocr.pdf

  -t, --tempdir TMPDIR_PATH set the path to directory with intermediate
                            files; Default: ~/tmp

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
                            double quotes e.g., "-c textord_min_linesize 2.5"

  -h, --help                print this

  -p, --parallel            use GNU parallel if available

END
}

function print_usage {
cat << END
pdfocr script

Usage:

  pdfocr -i|--input input.pdf [options...]

Options:

  -h, --help                print help
  -l, --lang "LANG"         set the language(s) for tesseract
  -o, --output OUTPUT_PATH  set the output path
  -t, --tempdir TMPDIR_PATH set the path to tempdir (def: ~/tmp)
  -m, --mode MODE           set the mode (split,ocr,merge,full)
  -c, --tess-config CONFIG  set the tesseract configuration; default: pdf
  -f, --img-format FMT      the format of the intermediate images; 
                              jpeg png* ppm tiff*
  -r, --resolution NUM      set the resolution of the intermediate images
      --tess-params "PARAMS"  set the tesseract parameters
      --keep-tmp            keep the intermediate files; deleted by default
  -p, --parallel            use GNU parallel if available

END

}

pdfocr $*

# vim: ts=2 sw=2
