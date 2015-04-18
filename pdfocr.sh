#! /bin/bash

INPUT=
declare -a INPUT_FILES
ARGUMENTS=( "$@" )
OUTPUT=
OUT_FINAL=
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

  if [ ${#ARGUMENTS[@]} -eq 0 ]; then
    print_usage
    exit
  fi

  parse_args

  check_req

  for input_file in "${INPUT_FILES[@]}"; do
    echo Input file: $input_file

    INPUT="$input_file"

    init

    pdfocr_proc

    echo " "

  done

  echo Finished

}

function pdfocr_proc {

  split

  ocr

  merge

  clean_tmp


}

function clean_tmp {

  if [ $KEEP_TMP = false ]; then

    if [ $MODE != split ]; then
      rm "$TMPDIR_PATH/$INPUT_BASENAME"*_gs.$IMG_FMT
    fi
    if [ $MODE != ocr ]; then
      rm "$TMPDIR_PATH/$INPUT_BASENAME"*_gs_tess.pdf
    fi

  fi
}

function split  {


  if [[ $MODE = @(full|split) ]];then
    echo Running ghostscript on $INPUT

    gs -dSAFER -dBATCH -dNOPAUSE -sDEVICE=$GSDEV -r$RES -dTextAlphaBits=4 \
      -o "$TMPDIR_PATH/$INPUT_BASENAME%04d_gs.$IMG_FMT" -f "$INPUT" > /dev/null

    try "Error while converting $INPUT"
    exit_on_mode $MODE
  fi

}
function ocr {

  if [[ $MODE = @(full|ocr) ]]; then

    local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
    if [ $PARALLEL = true ]; then
      echo Running tesseract on multiple cores
      export -f run_tess
      export TESS_PARAMS
      export TESS_LANG
      export TESS_CONFIG
      parallel run_tess ::: "$IN_P"*_gs.$IMG_FMT
      try "Error while performing ocr"
    else
      for f in "$IN_P"*_gs.$IMG_FMT; do
        echo Running tesseract
        run_tess "$f"
        try "Error while performing ocr"
        echo input $f 
        echo output ${f%.*}_tess.pdf
      done
    fi

    exit_on_mode $MODE
  fi


}
function merge {

  if [[ $MODE = @(full|merge) ]]; then

    local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
    local file_count=`ls -1 "$IN_P"*_gs_tess.pdf | wc -l`
    if [[ $file_count -gt 1 ]]; then
      echo merging into $OUT_FINAL
      pdfunite "$IN_P"*_gs_tess.pdf "$OUT_FINAL"
    fi
    try "Error while merging $fn into $OUT_FINAL"
  fi

}

function run_tess {
    tesseract "$1" "${1%.*}_tess" -l $TESS_LANG -psm 3 $TESS_PARAMS $TESS_CONFIG
}

function exit_on_mode {

  if [[ $1 = @(split|ocr) ]];then
    continue
  fi

}

function init {

  INPUT_BASENAME=$(basename "$INPUT")
  INPUT_BASENAME=${INPUT_BASENAME%.*}

  if [ -z "$OUTPUT" ]; then

    local INPUT_DIR=$(dirname "$INPUT")
    OUTPUT="$INPUT_DIR/$INPUT_BASENAME"_ocr.pdf

  else

    if [[ $OUTPUT =~ INPUT_BASENAME ]]; then
      OUT_FINAL=${OUTPUT/INPUT_BASENAME/$INPUT_BASENAME}
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

  local let in_c=-1
  local let v_c=0

  while [[ $v_c -lt ${#ARGUMENTS[@]} ]]; do

    key=${ARGUMENTS[$v_c]}
    
    if (( v_c < ${#ARGUMENTS[@]} ));then
      local val="${ARGUMENTS[$((v_c+1))]}"
    fi
    case $key in
    -*)
     let in_c=-1
     ;;& 
    -i|--input)
      let in_c=0
      ;;
    -o|--output)
      OUTPUT="$val"
      ;;
    -t|--tempdir)
      TMPDIR_PATH="$val"
      ;;
    -tess-config|-c)
      TESS_CONFIG="$val"
      ;;
    -l|--language)
      TESS_LANG="$val"
      ;;
    -r|--resolution)
      RES="$val"
      ;;
    -f|--img-format)
      GSDEV="$val"
      ;;
    --tess-params)
      TESS_PARAMS="$val"
      ;;
    --keep-tmp)
      KEEP_TMP=true
      ;;
    -m|--mode)
      MODE="$val"
      ;;
    -p|--parallel)
      if which parallel >/dev/null; then
        PARALLEL=true
      fi
      ;;
    -h|--help)
      print_help
      exit
      ;;
    *)
      if (( in_c > -1 )); then
        INPUT_FILES[$in_c]=$key
        let in_c++
      fi
      ;;
    esac
    let v_c++
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

  if [ ${#INPUT_FILES[@]} -eq 0 ]; then
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
                            double quotes e.g., "-c textord_min_linesize=2.5"

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

pdfocr

# vim: ts=2 sw=2
