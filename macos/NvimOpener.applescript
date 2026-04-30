on open theFiles
    set cmd to "exec nvim"
    repeat with f in theFiles
        set cmd to cmd & " " & quoted form of (POSIX path of f)
    end repeat
    do shell script "/usr/bin/open -na Ghostty --args -e /bin/zsh -l -c " & quoted form of cmd
end open
