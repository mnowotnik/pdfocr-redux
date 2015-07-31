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
JOBS=1
GSDEV=jpeg
INPUT_BASENAME=
TMPDIR_PATH=~/tmp
VERBOSE=false

RESET="\e[0m"
PENDING="\e[1;91m"
ERROR="\e[1;31m"
DONE="\e[1;36m"
MSG="\e[1;36m"

#regexes
shopt -s extglob

#kill child processes on error
trap 'end_jobs' EXIT

function pdfocr {

  if [ ${#ARGUMENTS[@]} -eq 0 ]; then
    print_usage
    exit
  fi

  parse_args

  check_req

  for input_file in "${INPUT_FILES[@]}"; do
    echo -e "${MSG}Input file:$RESET" `basename "$input_file"`

    if [[ $MODE = clean ]]; then
      echo Cleaning temp files...
    fi

    check_file "$input_file"

    init "$input_file"

    pdfocr_proc "$input_file"

    echo

  done

  echo -e "${DONE}Finished$RESET"

}

function pdfocr_proc {

  local input_file=$1

  split "$input_file"

  local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"

  if [[ -n $PREPROCESSOR ]]; then
    preprocess "$IN_P" "$IMG_FMT"
  fi

  ocr "$IN_P" "$IMG_FMT"

  merge "$IN_P"

  clean_tmp "$IN_P" "$IMG_FMT"


}

function split  {

  if ! [[ $MODE = @(full|split) ]];then
    return
  fi

  echo -e ${PENDING}Running$RESET ghostscript

  local IN_F=$1

  local GS_OUT="$TMPDIR_PATH/$INPUT_BASENAME%04d_gs.$IMG_FMT"
  gs -dSAFER -dBATCH -dNOPAUSE -sDEVICE=$GSDEV -r$RES -dTextAlphaBits=4 \
    -o "$GS_OUT" -f "$IN_F" > /dev/null

  try "Error while converting $IN_F"
}

function preprocess {

  if [ $PARALLEL = true ]; then
    echo -e ${PENDING}Running$RESET preprocessor in parallel
    export -f run_preproc
    export -f try
    local PRE4PARA=`parallel --shellquote ::: "$PREPROCESSOR"`
    parallel -n 1 -d ::: -j $JOBS -m run_preproc "$PRE4PARA" {} ::: "$1"*_gs."$2"
    try "Error during parallel preprocessing!"
  else
    echo -e ${PENDING}Running$RESET preprocessor
    for f in "$1"*_gs."$2";do
        run_preproc "$PREPROCESSOR" "$f"
    done
  fi

}

function ocr {

  if ! [[ $MODE = @(full|ocr) ]]; then
    return 
  fi

  local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
  if [ $PARALLEL = true ]; then
    echo -e ${PENDING}Running$RESET tesseract in parallel
    if [ "$VERBOSE" = false ];then
      run_wait
    fi

    export -f run_tess
    export -f try
    export -f print_errors

    if [ -z "$TESS_PARAMS" ]; then
      TESS_PARAMS=" "
    fi

    local ESC=`echo $TESS_PARAMS| sed 's/-/__-/'`
    ESC=`parallel --shellquote ::: "$ESC"`
    parallel -n1 -j $JOBS -m run_tess {} "$TESS_LANG" "$ESC" "$TESS_CONFIG" "$VERBOSE" ::: "$1"*_gs."$2"
    try "Error while running parallel tesseract jobs!"

    if [ "$VERBOSE" = false ]; then
      kill -INT $!
    fi

  else
    echo -e ${PENDING}Running$RESET tesseract
    if [ "$VERBOSE" = false ];then
      run_wait
    fi

    for f in "$1"*_gs."$2"; do
      run_tess "$f" "$TESS_LANG" "$TESS_PARAMS" "$TESS_CONFIG" "$VERBOSE"
    done

    if [ "$VERBOSE" = false ]; then
      kill -INT $!
    fi
  fi


}

function merge {

  if ! [[ $MODE = @(full|merge) ]]; then
    return
  fi

  # local IN_P="$TMPDIR_PATH/$INPUT_BASENAME"
  local file_count=`ls -1 "$1"*_gs_tess.pdf | wc -l`
  echo -e ${PENDING}Merging$RESET into $OUT_FINAL
  if [[ $file_count -gt 1 ]]; then
    pdfunite "$1"*_gs_tess.pdf "$OUT_FINAL"
  else
    cp "$1"*_gs_tess.pdf "$OUT_FINAL"
  fi
  try "Error while merging $1"*"$2 into $OUT_FINAL"
}

function clean_tmp {
  if [ $KEEP_TMP = true ]; then
    return
  fi

  if [[ $MODE != split ]]; then
    rm "$1"*_gs."$2"
  fi
  if [[ $MODE != ocr ]]; then
    rm "$1"*_gs_tess.pdf
  fi
}


function run_wait {

  export -f wait_anim
  wait_anim &

}

function run_tess {
  local IN=$1
  local TESS_LANG=$2
  local TESS_PARAMS=$3
  TESS_PARAMS=`echo $TESS_PARAMS | sed 's/__-/-/'`
  local TESS_CONFIG=$4
  local VERBOSE=$5
  local tess_o=
  if [ "$VERBOSE" = true ]; then
    echo tesseract "$IN" "${IN%.*}_tess" -l $TESS_LANG -psm 3 $TESS_PARAMS $TESS_CONFIG
fi

  tess_o=$(tesseract "$IN" "${IN%.*}_tess" -l $TESS_LANG -psm 3 $TESS_PARAMS $TESS_CONFIG   2>&1)
  try "Error while performing ocr!" "$tess_o"

  if [ "$VERBOSE" = true ]; then
    echo $tess_o
    echo Tesseract input $1 
    echo Tesseract output ${1%.*}_tess.pdf
  fi
}

function run_preproc {
      local PAGE_NUM=`echo $2|gawk 'match($0,/.+([0-9]{4})_gs.*/,arr) { print arr[1]}'`
      $1 "$2" $PAGE_NUM
      try "Error while preprocessing!" "Preprocessor: $1" "Input file: $2"
}

function init {

  local INPUT=$1

  INPUT_BASENAME=$(basename "$INPUT")
  INPUT_BASENAME=${INPUT_BASENAME%.*}

  if [ -z "$OUTPUT" ]; then

    local INPUT_DIR=$(dirname "$INPUT")
    OUT_FINAL="$INPUT_DIR/$INPUT_BASENAME"_ocr.pdf

  else

    if [[ "$OUTPUT" =~ INPUT_BASENAME ]]; then
      OUT_FINAL="${OUTPUT/INPUT_BASENAME/$INPUT_BASENAME}"
    elif [[ "${OUTPUT: -1}" == "/" ]]; then
      OUT_FINAL="$OUTPUT$INPUT_BASENAME"_ocr.pdf
      OUTPUT_DIR=$OUTPUT
    else
      OUT_FINAL=$OUTPUT
    fi

    if [ -z $OUTPUT_DIR ]; then
      local OUTPUT_DIR=$(dirname $OUTPUT)
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
      mkdir -p "$OUTPUT_DIR"
      try "Failed creating the output directory: $OUTPUT_DIR"
    fi

  fi

  if [ ! -d "TMPDIR_PATH" ]; then
    mkdir -p "$TMPDIR_PATH"
    try "Failed creating the temporary directory: $TMPDIR_PATH"
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
    --tess-config)
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
    -c|--tess-param)
      TESS_PARAMS="$TESS_PARAMS -c $val"
      ;;
    --keep-tmp)
      KEEP_TMP=true
      ;;
    -m|--mode)
      MODE="$val"
      ;;
    -p|--parallel)
      if hash parallel 2>/dev/null; then
        PARALLEL=true
        if [[ -n $val ]]; then
          JOBS=$val
        else
          JOBS=`parallel --number-of-cores`
        fi
      fi
      ;;
    -s|--preprocessor)
      PREPROCESSOR=$val
      ;;
    -v|--verbose)
      VERBOSE=true
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

  if ! [[ $MODE = @(split|full|ocr|merge|clean) ]];then
    echo "Invalid mode: $MODE"
    print_usage
    exit
  fi

}

function check_req {

  if ! hash pdfunite 2> /dev/null; then
    echo pdfunite missing!
    exit
  fi

  if ! hash tesseract 2> /dev/null; then
    echo tesseract missing!
    exit
  fi

  if ! hash gs 2> /dev/null; then
    echo ghostscript missing!
    exit
  fi

  if [ ${#INPUT_FILES[@]} -eq 0 ]; then
    echo pdf input path is missing!
    exit
  fi
}

function check_file {

  if ! [ -f "$1" ]; then
    throw "No such file: $1"
  fi

}

function try {

  if [[ $? -ne 0 ]] ; then
    print_errors "$@"
    exit 1
  fi
  return 0
}
 
function throw {

  print_errors "$@"
  exit 1
}

function print_errors {

  for msg; do
    echo -e "$ERROR$msg$RESET"
  done
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

      --tess-config         set the tesseract configuration; default: pdf

  -p, --parallel [JOBS]     use GNU parallel if available; limit the number
                            of jobs to JOBS

  -v, --verbose             allow verbose output

      --keep-tmp            keep the intermediate files; deleted by default

  -f, --img-format          the format of the intermediate images; 
                            possible values:
                              jpeg png* ppm tiff*
                            any format supported by Ghostscript that matches
                            the above values is valid;
                            note: the image format makes a difference for
                            tesseract, so experiment with different values
                            Default: jpeg

  -r, --resolution  RES     set the resolution of intermediate images to RES;
                            default: 300

  -c, --tess-param key=val  set a tesseract parameter 
                            e.g., -c textord_min_linesize=2.5

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
  -l, --lang LANGS          set the language(s) for tesseract
  -o, --output OUTPUT_PATH  set the output path
  -t, --tempdir TMPDIR_PATH set the path to tempdir (def: ~/tmp)
  -m, --mode MODE           set the mode (split,ocr,merge,full)
      --tess-config CONFIG  set the tesseract configuration; default: pdf
  -f, --img-format FMT      the format of the intermediate images; 
                              jpeg png* ppm tiff*
  -r, --resolution NUM      set the resolution of the intermediate images
  -c, --tess-param key=val  set a tesseract parameter
      --keep-tmp            keep the intermediate files; deleted by default
  -p, --parallel [JOBS]     use GNU parallel if available
  -v, --verbose             allow verbose output
  -s, --preprocessor PROC_PATH set the path to images preprocessor

END

}

function wait_anim {

  trap "__STOP_PRINT=true" SIGINT
  local move=r
  local let length=5
  local let pos=0
  while [[ $__STOP_PRINT != true ]]; do

    echo -en " |"

    for ((i=0;i<pos;i++));do
      echo -n " "
    done

    echo -en "$PENDING*$RESET"

    for ((i=0;i<length-pos;i++));do
      echo -n " "
    done

    echo -en "|"
    echo -ne \\r


    if [[ $move == r ]]; then
      let pos++
      if ((pos>=length)); then
        move=l
      fi
    else
      let pos--
      if ((pos<=0)); then
        move=r
      fi
    fi

    sleep 0.07
  done
}

function end_jobs {

  local job_n=`jobs -p | wc -l`
  if ((job_n>0)); then
    jobs -p | xargs kill
  fi

}

pdfocr
trap '' EXIT SIGINT

# vim: ts=2 sw=2
