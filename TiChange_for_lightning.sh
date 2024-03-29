function TiChange_help(){
   echo "Auther    : jan su"
   echo "Introduce : TiChange_for_lightning 是一个能让你快速将csv文件适配 tidb-lightning csv 文件格式要求的工具，如有任何 BUG 请及时反馈，作者将及时修复！"
   echo " "
   echo "Usage: ${0##*/} [option] [parameter]"
   echo "option: -i --input-file          [input_csv_path]          |               | 需要处理的csv文件路径;"
   echo "        -o --operate-path        [operate_dir_path]        |               | 需要处理csv文件的，空间足够的文件夹路径;"
   echo "        -m --schema-meta         [schema_meta]             |               | 需要指定库中 csv 文件所属对象信息，eg: -m schema_name.table_name;"
   echo "        -s --separator_import    [separator_import_format] |(default: ',' )| 需要指定当前 csv 文件字段分隔符，eg: -s '||' TiChange 自动将其转换为 \",\" : \"A\"||\"B\" --> \"A\",\"B\" ;"
   echo "        -d --delimiter_import    [delimiter_import_format] |(default: '\"' )| 需要指定当前 csv 文件引用定界符，eg: -d  ''  TiChange 自动将其转换为 '\"' :    ABC   -->  \"ABC\" ;"
   echo "        -n --null_import         [null_import_format]      |(default: '\N')| 需要指定解析 csv 文件中字段值为 NULL 的字符， eg: '\\N' 导入 TiDB 中会被解析为 NULL ;"
   echo "        -c --collect_dir         [collect_dir]             |(default: '')  | 指定拆分后的csv文件汇总目录，比如拆分多个文件到同一个目录中，再用lightning一次性导入"
   echo "        -h --help                                          |               | 获取关于 TiChange.sh 的操作指引，详细 Demo 请参考 ： https://github.com/jansu-dev/TiChange_for_lightning;"
}


# Deal with content of input
if [ $# -le 0 ] || [ $1 = '?' ]; then
   TiChange_help
   exit 1
fi



# Get an hash string for copying file
hash_time=$(date "+%Y%m%d%H%M%S" | tr -d '\n' | md5sum)
perfix_hash_time=${hash_time:0:7}

# Set TiChange options using getopt lib
TEMP=`getopt -o i:o:s:m:d:n:c:h --long help,input-file:,operate-path:,schema-meta:,separator_import:,delimiter_import:,null_import:,collect_dir: -- "$@"`

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

# Default value
TiChange_separator=','
TiChange_delimiter='"'
TiChange_null='\N'
TiChange_collect_dir=''

while true ; do
        case "$1" in
                -i|--input-file)          echo "Option i == ${2}" ; 
			Source_oper_file=${2}; shift 2;;
                -o|--operate-path)        echo "Option o == ${2}" ;
                        TiChange_check_dir=${2}
			TiChange_oper_file=${2}/TiChange_operating_csv_$perfix_hash_time;
                        TiChange_oper_dir=${2}/${perfix_hash_time}_operating_dir; shift 2;;
                -m|--schema-meta)         echo "Option m == ${2}" ;
			TiChange_meta_table=${2}; shift 2;;
                -s|--separator_import)    echo "Option s == ${2}" ;
			TiChange_separator=${2}; shift 2;;
                -d|--delimiter_import)    echo "Option d == ${2}" ;
			TiChange_delimiter=${2}; shift 2;;
                -n|--null_import)         echo "Option n == ${2}" ;
			TiChange_null=${2}; shift 2;;
                -c|--collect_dir)         echo "Option c == ${2}" ;
			TiChange_collect_dir=${2}; shift 2;;
                -h|--help) TiChange_help; exit 1 ;;
                --) shift ; break ;;
                *) echo "Internal error!" ; exit 1 ;;
        esac
done

# Check the file or dir
if [ ! -d ${TiChange_check_dir} ] || [ ! -f ${Source_oper_file} ]; then
        echo "The \"operate-path\" or \"input-file\" isn't exists, please retry it using right parameter!"
        exit 1
fi

# Print information on terminal
echo "---------------------------------------------------------------------------"
echo "------------  TiChange starting  ------------------------------------------"

# Change input csv file to "mofidy_dir" for operating
cp ${Source_oper_file} ${TiChange_oper_file}

# Deal with TiChange_oper_file turned into adopted format of lightning
# Deal with the delimiter of files
if [ ! ${TiChange_delimiter} ]; then
        # if delimiter is null and separator is tab, blankspace or others
        TiChange_delimiter_up_end_pattern="s#^|\$#\"#g"
        sed -ri ${TiChange_delimiter_up_end_pattern} ${TiChange_oper_file} 
        TiChange_delimiter_interal_pattern="s#${TiChange_separator}#\",\"#g"
        sed -i ${TiChange_delimiter_interal_pattern} ${TiChange_oper_file}
elif [ ${TiChange_delimiter} != '"' ]; then
        # if delimiter is not null
        TiChange_delimiter_up_end_pattern="s#^${TiChange_delimiter}|\$${TiChange_delimiter}#\"#g"
        sed -ri ${TiChange_delimiter_up_end_pattern} ${TiChange_oper_file} 
        TiChange_delimiter_interal_pattern="s#${TiChange_delimiter}${TiChange_separator}${TiChange_delimiter}#\",\"#g"
        sed -i ${TiChange_delimiter_interal_pattern} ${TiChange_oper_file}
fi


# Deal with NULL value using sed Command
if [ ${TiChange_null} ]; then
        sed -i 's#""#\\N#g' ${TiChange_oper_file}
elif [ ${TiChange_null} != '\N' ]; then
        sed -i "s#\"${TiChange_null}\"#\\\\N#g" ${TiChange_oper_file}
fi


# Split the file into many small files, which 
# is similer to number of cpu processor(vCore)
mkdir ${TiChange_oper_dir}
cd ${TiChange_oper_dir}
TiChange_lines=`cat ${TiChange_oper_file} |wc -l`
TiChange_vCore_number=`cat /proc/cpuinfo |grep "processor"|wc -l`
TiChange_lines_per_file=`expr ${TiChange_lines} / ${TiChange_vCore_number}`
split -l `expr ${TiChange_lines_per_file} + 1` ${TiChange_oper_file}  -d -a 8 ${TiChange_meta_table}.
rm -rf ${TiChange_oper_file}

# Change every files to obey the filename named rule of tidb-lightning
softfiles=$(ls ${TiChange_oper_dir})
for sfile in ${softfiles}
do
   mv ${sfile} ${sfile}.csv
done

if [ -n "${TiChange_collect_dir}"]; then   
   if [ ! -d "${TiChange_collect_dir}" ]; then
      mkdir -p ${TiChange_collect_dir}
   fi
   mv *.csv ${TiChange_collect_dir}/
   cd -
   rm -rf ${TiChange_oper_dir}
   TiChange_oper_dir=${TiChange_collect_dir}
fi

echo "---------------------------------------------------------------------------"
echo "------------  using below information for tidb-lightning.toml  ------------"
echo "---------------------------------------------------------------------------"
echo "Please write the string path to tidb-lightning.toml config file!!!"
echo "and ,delete the dealed files by hand after imported data into database!!!"
echo -e "\n"
echo "[mydumper]"
echo "data-source-dir = \"${TiChange_oper_dir}\"" 
echo "[mydumper]"
echo "no-schema = true"
echo "---------------------------------------------------------------------------"

# Delete all of tmp splited file
#ls ${2} | grep ${perfix_hash_time} |xargs rm -rf
