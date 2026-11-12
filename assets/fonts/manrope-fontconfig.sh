# Sourced by the asset generators that render text with Inkscape. Points
# fontconfig at the repo's generated Manrope TTFs (packages/ui_kit/fonts) so
# the brand art renders in the product face without a system-wide install,
# and refuses to continue if the face cannot be resolved: a silent fallback
# would change the brand. Expects $WORK (a temp dir) and $REPO_ROOT.
cat > "$WORK/fonts.conf" <<CONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <dir>$REPO_ROOT/packages/ui_kit/fonts</dir>
  <cachedir>$WORK/fc-cache</cachedir>
</fontconfig>
CONF
export FONTCONFIG_FILE="$WORK/fonts.conf"
fc-list : family | grep -qx "Manrope" || { echo "error: Manrope not found; run assets/fonts/gen-manrope.py" >&2; exit 1; }
