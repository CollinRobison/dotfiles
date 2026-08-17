# Shell path additions for rootless Linux workstation tools.
# Safe to source from Bash or Zsh.
for dotfiles_path in "$HOME/.local/bin" "$HOME/.local/share/nvim/mason/bin"; do
  case ":${PATH:-}:" in
    *":${dotfiles_path}:"*) ;;
    *) PATH="${dotfiles_path}${PATH:+:${PATH}}" ;;
  esac
done
export PATH
