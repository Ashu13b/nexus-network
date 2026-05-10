# ── Remote OCR (Ubuntu) ──

mobocr() {
    local img="$1"
    [ ! -f "$img" ] && { echo "Usage: mobocr <image_path>"; return 1; }

    echo -e "${C_CYAN}[OCR]${C_RESET} Sending $img to Ubuntu Server..."

    ssh -T ubu '
        tmpfile=$(mktemp /tmp/ocrimgXXXXXX)
        cat > "$tmpfile"
        /home/ubuntu/.local/bin/ocr-test "$tmpfile"
        rm -f "$tmpfile"
    ' < "$img"
}
