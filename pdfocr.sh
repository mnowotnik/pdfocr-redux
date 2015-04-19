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
JOBS=0
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

    if [[ $MODE != split ]]; then
      rm -f "$TMPDIR_PATH/$INPUT_BASENAME"*_gs.$IMG_FMT
    fi
    if [[ $MODE != ocr ]]; then
      rm -f "$TMPDIR_PATH/$INPUT_BASENAME"*_gs_tess.pdf
    fi

  fi
}

function split  {


  if [[ $MODE = @(full|split) ]];then
    echo Running ghostscript

    local GS_OUT="$TMPDIR_PATH/$INPUT_BASENAME%04d_gs.$IMG_FMT"
    gs -dSAFER -dBATCH -dNOPAUSE -sDEVICE=$GSDEV -r$RES -dTextAlphaBits=4 \
      -o "$GS_OUT" -f "$INPUT" > /dev/null

    try "Error while converting $INPUT"
  fi

  if [[ -n $PREPROCESSOR ]]; then
    preprocess
  fi

  exit_on_mode $MODE

}
function ocr {

  if [[ $MODE = @(full|ocr) ]]; then

    local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
    if [ $PARALLEL = true ]; then
      echo Running tesseract on multiple cores
      export -f run_tess
      export -f try
    fi
    for f in "$IN_P"*_gs.$IMG_FMT; do
      if [ $PARALLEL = true ]; then
        echo file$f
        parallel -n 4 -j $JOBS run_tess ::: "$f" "$TESS_LANG" "$TESS_PARAMS" "$TESS_CONFIG"
      else
        run_tess "$f" "$TESS_LANG" "$TESS_PARAMS" "$TESS_CONFIG"
      fi
    done

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

function preprocess {

  local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
  if [ $PARALLEL = true ]; then
    export -f run_preproc
  fi
  for f in "$IN_P"*_gs.$IMG_FMT; do
    if [ $PARALLEL = true ]; then
      parallel -n 2 -j $JOBS run_preproc ::: "$f" "$PREPROCESSOR"
    else
      run_preproc $f
    fi
  done

}

function run_tess {
  local IN=$1
  local TESS_LANG=$2
  local TESS_PARAMS=$3
  local TESS_CONFIG=$4
  tesseract "$IN" "${IN%.*}_tess" -l $TESS_LANG -psm 3 $TESS_PARAMS $TESS_CONFIG
  try "Error while performing ocr"
  echo input $1 
  echo output ${1%.*}_tess.pdf
}

function run_preproc {
      local PAGE_NUM=`echo $1|gawk 'match($0,/.+([0-9]{4})_gs.*/,arr) { print arr[1]}'`
      "$2" "$1" $PAGE_NUM
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
    OUT_FINAL="$INPUT_DIR/$INPUT_BASENAME"_ocr.pdf

  else

    if [[ $OUTPUT =~ INPUT_BASENAME ]]; then
      OUT_FINAL=${OUTPUT/INPUT_BASENAME/$INPUT_BASENAME}
    else
      OUT_FINAL=$OUTPUT
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

  local let in_c=0
  local let v_c=0

  local LANGS_ARR=()
  local IN_ARG=

  while [[ $v_c -lt ${#ARGUMENTS[@]} ]]; do

    key=${ARGUMENTS[$v_c]}
    
    if (( v_c < ${#ARGUMENTS[@]} ));then
      local val="${ARGUMENTS[$((v_c+1))]}"
      if [[ $val == -* ]]; then
        val=
      fi

    fi
    case $key in
    -*)
      IN_ARG=
      let in_c=0
     ;;& 
    -i|--input)
      IN_ARG=INPUT
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
      IN_ARG=TESS_LANG
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
        if [[ -n $val ]]; then
          JOBS=$val
        fi
      fi
      ;;
    -s|--preprocessor)
      PREPROCESSOR=$val
      ;;
    -h|--help)
      print_help
      exit
      ;;
    *)
      case $IN_ARG in
      INPUT)
        INPUT_FILES[$in_c]=$key
        let in_c++
        ;;
      TESS_LANG)
        LANGS_ARR[$in_c]=$key
        let in_c++
      esac
      ;;
    esac
    let v_c++
  done

  if [[ ${#LANGS_ARR} -gt 0 ]]; then
    TESS_LANG="${LANGS_ARR[@]}"
    TESS_LANG=`echo "$TESS_LANG"|sed 's/ /+/'`
  fi

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

  if [[ $? -ne 0 ]] ; then
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


END
}

function print_usage {
cat << END
pdfocr script

Usage:

  pdfocr -i|--input input.pdf [options...]

Options:

  -h, --help                print help
  -l, --lang LANGS         set the language(s) for tesseract
  -o, --output OUTPUT_PATH  set the output path
  -t, --tempdir TMPDIR_PATH set the path to tempdir (def: ~/tmp)
  -m, --mode MODE           set the mode (split,ocr,merge,full)
  -c, --tess-config CONFIG  set the tesseract configuration; default: pdf
  -f, --img-format FMT      the format of the intermediate images; 
                              jpeg png* ppm tiff*
  -r, --resolution NUM      set the resolution of the intermediate images
      --tess-params "PARAMS"  set the tesseract parameters
      --keep-tmp            keep the intermediate files; deleted by default
  -p, --parallel [JOBS]     use GNU parallel if available
  -s, --preprocessor PROC_PATH set the path to images preprocessor

END

}

pdfocr

# vim: ts=2 sw=2
