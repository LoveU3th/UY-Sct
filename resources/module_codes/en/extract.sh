function extract_single_img {
  local single_file="$1"
  local single_file_name=$(basename "$single_file")
  local base_name="${single_file_name%.*}"
  fs_type=$(recognize_file_type "$single_file")
  start=$(python3 "$TOOL_DIR/get_right_time.py")

  # Clean the target folder before extraction
  if [[ "$fs_type" == "ext" || "$fs_type" == "erofs" || "$fs_type" == "f2fs" || \
        "$fs_type" == "boot" || "$fs_type" == "dtbo" || "$fs_type" == "recovery" || \
        "$fs_type" == "vbmeta" || "$fs_type" == "vendor_boot" ]]; then
    rm -rf "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
  fi

  case "$fs_type" in
    sparse)
      echo "Converting sparse partition file ${single_file_name}, please wait..."
      "$TOOL_DIR/simg2img" "$single_file" "$WORK_DIR/$current_workspace/${base_name}_converted.img"
      rm -rf "$single_file"
      mv "$WORK_DIR/$current_workspace/${base_name}_converted.img" "$WORK_DIR/$current_workspace/${base_name}.img"
      single_file="$WORK_DIR/$current_workspace/${base_name}.img"
      echo "${single_file_name} 转换完成"
      extract_single_img "$single_file"
      return
      ;;
    super)
      echo "Extracting SUPER partition file ${single_file_name}, please wait..."
      
      # Read the byte size of the super file
      super_size=$(stat -c%s "$single_file")
      
      # Create the config folder and write the original_super_size file
      mkdir -p "$WORK_DIR/$current_workspace/Extracted-files/config"

      if [ ! -s "$WORK_DIR/$current_workspace/Extracted-files/config/original_super_size" ]; then
        echo "$super_size" > "$WORK_DIR/$current_workspace/Extracted-files/config/original_super_size"
      fi
      
      "$TOOL_DIR/7z" e -bb1 -aoa "$single_file" -o"$WORK_DIR/$current_workspace"
      rm "$single_file"
      mkdir -p "$WORK_DIR/$current_workspace/Extracted-files/super"
      echo "${single_file_name} extraction completed"
      ;;
    boot|dtbo|recovery|vbmeta|vendor_boot)
      echo "Extracting partition file ${single_file_name}, please wait..."
      rm -rf "$TOOL_DIR/boot_editor/build"
      cp "$single_file" "$TOOL_DIR/boot_editor/$single_file_name"
      (cd "$TOOL_DIR/boot_editor" && ./gradlew unpack) > /dev/null 2>&1
      rm -rf "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      mkdir -p "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      mv -f "$TOOL_DIR/boot_editor/build/unzip_boot"/* "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      mv -f "$TOOL_DIR/boot_editor/$base_name.img" "$TOOL_DIR/boot_editor/$base_name.img.wait"
      echo "${single_file_name} extraction completed"
      ;;
    f2fs)
      echo "Extracting partition file ${single_file_name}, please wait..."
      "$TOOL_DIR/extract.f2fs" "$single_file" -o "$WORK_DIR/$current_workspace/Extracted-files" > /dev/null 2>&1
      echo "${single_file_name} extraction completed"
      ;;
    erofs)
      echo "Extracting partition file ${single_file_name}, please wait..."
      "$TOOL_DIR/extract.erofs" -i "$single_file" -o "$WORK_DIR/$current_workspace/Extracted-files" -x > /dev/null 2>&1
      echo "${single_file_name} extraction completed"
      ;;
    ext)
      echo "Extracting partition file ${single_file_name}, please wait..."
      PYTHONDONTWRITEBYTECODE=1 python3 "$TOOL_DIR/ext4_info_get.py" "$single_file" "$WORK_DIR/$current_workspace/Extracted-files/config"
      rm -rf "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      mkdir -p "$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      "$TOOL_DIR/extract.ext" "$single_file" "./:$WORK_DIR/$current_workspace/Extracted-files/$base_name"
      echo "${single_file_name} extraction completed"
      ;;
    payload)
      echo "Extracting ${single_file_name}, please wait..."
      "$TOOL_DIR/payload-dumper-go" -c 4 -o "$WORK_DIR/$current_workspace" "$single_file" > /dev/null 2>&1
      rm -rf "$single_file"
      echo "${single_file_name} extraction completed"
      ;;
    zip) 
      file_list=$("$TOOL_DIR/7z" l "$single_file") 
      if echo "$file_list" | grep -q "payload.bin" && echo "$file_list" | grep -q "META-INF"; then 
        echo "Detected ROM package ${single_file_name}, please wait..." 
        "$TOOL_DIR/7z" e -bb1 -aoa "$single_file" "payload.bin" -o"$WORK_DIR/$current_workspace" 
        extract_single_img "$WORK_DIR/$current_workspace/payload.bin" 
        rm -rf "$single_file" 
        return 
      elif echo "$file_list" | grep -q "images/" && echo "$file_list" | grep -q ".img"; then 
        echo "Detected ROM package ${single_file_name}, please wait..." 
        "$TOOL_DIR/7z" e -bb1 -aoa "$single_file" "images/*.img" -o"$WORK_DIR/$current_workspace" 
        rm -rf "$single_file" 
        echo "${single_file_name} extraction completed" 
      elif echo "$file_list" | grep -qE "AP|BL|CP|CSC"; then 
        echo "Detected Odin format ROM package ${single_file_name}, please wait..." 
        "$TOOL_DIR/7z" e -bb1 -aoa "$single_file" -o"$WORK_DIR/$current_workspace" -ir'!AP*' -ir'!BL*' -ir'!CP*' -ir'!CSC*' 
        for extracted_file in "$WORK_DIR/$current_workspace"/{AP*,BL*,CP*,CSC*}; do 
          if [ -f "$extracted_file" ]; then 
            fs_type=$(recognize_file_type "$extracted_file") 
            if [ "$fs_type" == "tar" ]; then 
              extract_single_img "$extracted_file" 
            fi 
          fi 
        done 
        rm -rf "$single_file" 
        return 
      else 
        echo "${single_file_name} may not be a flashable ROM package" 
      fi 
      ;; 
    tar) 
      echo "Extracting TAR file ${single_file_name}, please wait..." 
      "$TOOL_DIR/7z" x "$single_file" -o"$WORK_DIR/$current_workspace" -xr'!meta-data' 
      rm -rf "$single_file" 
      echo "${single_file_name} extraction completed" 
      found_lz4=false 
      for lz4_file in "$WORK_DIR/$current_workspace"/*.lz4; do 
        if [ -f "$lz4_file" ]; then 
          extract_single_img "$lz4_file" 
          found_lz4=true 
        fi 
      done 
      if [ "$found_lz4" = true ]; then 
        return 
      fi 
      ;; 
    lz4) 
      echo "Extracting LZ4 file ${single_file_name}, please wait..." 
      lz4 -dq "$single_file" "$WORK_DIR/$current_workspace/${base_name}" 
      rm -rf "$single_file" 
      echo "${single_file_name} extraction completed" 
      ;; 
    *) 
      echo "Unknown file system type" 
      ;; 
  esac 

  for file in "$WORK_DIR/$current_workspace"/*; do
    base_name=$(basename "$file")
    if [[ ! -s $file ]] || [[ $base_name == *_b.img ]] || [[ $base_name == *_b ]] || [[ $base_name == *_b.ext ]]; then
      rm -rf "$file"
    elif [[ $base_name == *_a.img ]]; then
      mv -f "$file" "${file%_a.img}.img"
    elif [[ $base_name == *_a.ext ]]; then
      mv -f "$file" "${file%_a.ext}.img"
    elif [[ $base_name == *.ext ]]; then
      mv -f "$file" "${file%.ext}.img"
    fi
  done

  end=$(python3 "$TOOL_DIR/get_right_time.py")
  runtime=$(echo "scale=3; if ($end - $start < 1) print 0; $end - $start" | bc)
  echo "Time taken: $runtime seconds"
}

function extract_img {
  keep_clean
  mkdir -p "$WORK_DIR/$current_workspace/Extracted-files/super"
  while true; do
    shopt -s nullglob
    regular_files=("$WORK_DIR/$current_workspace"/*.{bin,img})
    specific_files=("$WORK_DIR/$current_workspace"/*.{zip,lz4,tar,md5})
    matched_files=("${regular_files[@]}" "${specific_files[@]}")
    shopt -u nullglob
    if [ -e "${matched_files[0]}" ]; then
      displayed_files=()
      counter=0
      img_only=true
      for i in "${!matched_files[@]}"; do
        if [ -f "${matched_files[$i]}" ]; then
          fs_type=$(recognize_file_type "${matched_files[$i]}")
          if [ "$fs_type" != "unknown" ]; then
            displayed_files+=("${matched_files[$i]}")
            counter=$((counter+1))
            if [[ ! "${matched_files[$i]}" =~ \.img$ ]]; then
              img_only=false
            fi
          fi
        fi
      done
      while true; do
        echo -e "\n   Files in the current workspace:\n"
        for i in "${!displayed_files[@]}"; do
          fs_type_upper=$(echo "$(recognize_file_type "${displayed_files[$i]}")" | awk '{print toupper($0)}')
          printf "   \033[92m[%02d] %s —— %s\033[0m\n\n" "$((i+1))" "$(basename "${displayed_files[$i]}")" "$fs_type_upper"
        done
        if $img_only; then
          echo -e "   [ALL] Extract all    [S] Simple identify    [Q] Return to previous menu\n"
        else
          echo -e "   [S] Simple identify    [Q] Return to previous menu\n"
        fi
        echo -n "   Please select the partition file to extract:"
        read choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        if [ "$choice" = "all" ] && $img_only; then
          clear
          for file in "${displayed_files[@]}"; do
            echo -e "\n"
            extract_single_img "$file"
          done
          echo -n "Press any key to return to the workspace menu..."
          read -n 1
          clear
          return
        elif [ "$choice" = "s" ]; then
          mkdir -p "$WORK_DIR/$current_workspace/Ready-to-flash/images"
          for file in "$WORK_DIR/$current_workspace"/*.{img,elf,melf,mbn,bin,fv,pit}; do
            filename=$(basename "$file")
            if [ -f "$WORK_DIR/$current_workspace/optics.img" ]; then
              if [ "$filename" != "super.img" ] && [[ "$filename" != vbmeta*.img ]] && [[ "$filename" != "optics.img" ]] && [[ "$filename" != "vendor_boot.img" ]] && ! grep -q "$filename" "$TOOL_DIR/super_search"; then
                mv "$file" "$WORK_DIR/$current_workspace/Ready-to-flash/images/" 2>/dev/null
              fi
            else
              if [ "$filename" != "super.img" ] && ! grep -q "$filename" "$TOOL_DIR/super_search"; then
                mv "$file" "$WORK_DIR/$current_workspace/Ready-to-flash/images/" 2>/dev/null
              fi
            fi
          done
          clear
          break
        elif [ "$choice" = "q" ]; then
          return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#displayed_files[@]} ]; then
          file="${displayed_files[$((choice-1))]}"
          if [ -f "$file" ]; then
            clear
            echo -e "\n"
            extract_single_img "$file"
            echo -n "Press any key to return to the file list..."
            read -n 1
            clear
            break
          else
            echo "   The selected file does not exist."
          fi
        else
          clear
          echo -e "\n   Invalid choice, please re-enter."
        fi
      done
    else
      echo -e "\n   There are no files in the workspace."
      echo -n "   Press any key to return to the workspace menu..."
      read -n 1
      return
    fi
  done
}

