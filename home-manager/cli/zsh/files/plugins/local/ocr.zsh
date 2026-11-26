if (( ! $+commands[tesseract] ))
then
  # pacman -S tesseract tesseract-data-eng tesseract-data-deu tesseract-data-fra
  return
fi

zsh::autoload-dir ocr
