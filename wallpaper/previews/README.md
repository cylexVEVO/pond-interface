These baseline JPEG previews are generated from the bundled originals. They
provide the first wallpaper frame while Qt decodes the screen-sized original.

Regenerate after changing bundled wallpapers (requires PyQt6):

```sh
python3 wallpaper/preview.py
```

Custom images use the same generator when selected, with previews stored in
`$XDG_CACHE_HOME/pond-interface/wallpaper-previews` (or `~/.cache`). The cache key
includes the source path, modification time, and size. Preview failures fall
back to the original image.
