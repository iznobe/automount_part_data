#!/bin/bash

# ----------------------------------------------------------------------------
# "LICENCE BEERWARE" (Révision 42):
# <iznobe@forum.ubuntu-fr.org> a créé ce fichier. Tant que vous conservez cet avertissement,
# vous pouvez faire ce que vous voulez de ce truc. Si on se rencontre un jour et
# que vous pensez que ce truc vaut le coup, vous pouvez me payer une bière en
# retour.
# ----------------------------------------------------------------------------

do_change="yes" # "yes" or "no"

err() {
    >&2 echo -e "\\033[1;31m Erreur : $* \\033[0;0m"
}

info() {
  >&2 echo -e "\\033[0;33m Info : $* \\033[0;0m"
}

blue() {
  >&2 echo -e "\\033[1;34m  $* \\033[0;0m"
}

sav_file() {
  test -f "$1" || return 0
  if test "$do_change" = "yes"; then
    echo "sauvegarde du fichier « $1 » en « $1.BaK$now_time » avant modifications"
    if test "$2" = "u"; then sudo -u "$SUDO_USER" cp -v "$1" "$1".BaK"$now_time"
    else cp -v "$1"  "$1".BaK"$now_time"; fi
  fi
}

log_file() {
  test -f "$1" || return 0
  if test "$do_change" = "yes"; then
    test "$2" = "a" && sudo -u "$SUDO_USER" echo -e "$1 APRES modifications :" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
    test "$2" = "b" && sudo -u "$SUDO_USER" echo -e "$1 AVANT modifications :" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
    sudo -u "$SUDO_USER" cat -n "$1" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
  fi
}

checkLabel() {
test -n "$1" || return 1
local rgx="[^[:alnum:]_.-]"
if [[ $1 =~ $rgx || ${#1} -gt 16 ]]; then
    unset PartLabel
    return 1
fi
}

chooseLabel() {
  local rgx="[^[:alnum:]_.-]"

  while test -z "$newLabel"; do
    read -rp "Choisissez l’étiquette (LABEL) de votre partition de données, elle doit être UNIQUE et ne pas contenir d’espace, d’accent, de caractères spéciaux et au maximum 16 caractères : " newLabel
    if [[ $newLabel =~ $rgx || ${#newLabel} -gt 16 ]]; then
      err "le nom de votre étiquette comporte une espace, un accent ou un caractère spécial ou plus de 16 caractères !"
      unset newLabel
    fi
    for i in ${!ListPart[*]}; do
      if [[ $i == *,3 && ${ListPart[$i]} = "$newLabel" ]]; then
        err "votre étiquette « $newLabel » est déjà attribuée ! Choisissez-en une autre."
        unset newLabel
        break
      fi
    done
    blue "Vous avez entré « $newLabel »"
  done
}

delMountPoints() {
    local rgx="^(/mnt/|/media/).+$"
    declare -n parts=$1
    for part in "${parts[@]}"; do
        if test "$1" = 'mountedParts'; then umount -v "$part"; fi
        if test -d "$part"; then
            if [[ $part =~ $rgx ]]; then
                rmdir -v "$part"
            else
                echo "$part a été conservé."
            fi
        fi
        mapfile -t numLines < <(grep -En "$part"[[:space:]] /etc/fstab | cut -d ":" -f 1 | sort -rn)
        for n in "${numLines[@]}"; do
            sed -i "${n}d" /etc/fstab
        done
    done
}

urlencode() {
  local LANG=C i c e=''
  for ((i=0;i<${#1};i++)); do
    c=${1:$i:1}
    [[ "$c" =~ [a-zA-Z0-9\.\~\_\-] ]] || printf -v c '%%%02X' "'$c"
    e+="$c"
  done
  echo "$e"
}

if ((UID)); then
  err "Vous devez être super utilisateur pour lancer ce script (essayez avec « sudo $0 »)."
  exit 1
fi

LC_ALL=C
home="/home/$SUDO_USER"
now_time=$(date +"-%d-%m-%Y-%H-%M-%S")
if test "$do_change" = "yes"; then
log="$home/automount.log$now_time"
  sudo -u "$SUDO_USER" echo -e "$now_time" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
  sudo -u "$SUDO_USER" echo -e "home au depart :" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
  sudo -u "$SUDO_USER" ls -l  | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
fi
dir_tab=()
declare -A ListPart
declare -A Rgx=( [fstype]="^(ext[2-4]|ntfs)" [mountP]="^(/|/boot|/home|/tmp|/usr|/var|/srv|/opt|/usr/local)$" )
i=-1
q=0

while true; do
  read -rp "Voulez-vous utiliser le dossier « /media » pour monter la partition , si non , ce sera « /mnt »  [O/n]"
  case "$REPLY" in
    N|n)
      Mount="/mnt"
      break
    ;;
    Y|y|O|o|"")
      Mount="/media"
      break
    ;;
    *) err "Choix invalide";;
  esac
done
blue "Votre choix : $Mount"

while read -ra lsblkDT; do #path fstype hotplug mountpoint label
  if [[ ${lsblkDT[1]} =~ ${Rgx[fstype]} ]]; then
    if [[ ${lsblkDT[3]} =~ ${Rgx[mountP]} ]]; then
      continue
    else
      ((++i))
      ListPart[$i,0]="${lsblkDT[0]}" # path
      ListPart[$i,1]="${lsblkDT[1]}" # fstype
      ListPart[$i,2]="${lsblkDT[2]}" # hotplug
      if [[ ${lsblkDT[3]} =~ ^/ ]]; then # si mount point non vide
        ListPart[$i,3]="${lsblkDT[3]}" # mountpoint
        ListPart[$i,4]="${lsblkDT[4]}" # label
      else # si mount point est vide on decale la sortie avec une colonne en moins
        ListPart[$i,3]="             " # mountpoint vide
        ListPart[$i,4]="${lsblkDT[3]}" # label passe en indice 3 à la place du mountpoint
      fi
    fi
  fi
done < <(lsblk -no path,fstype,hotplug,mountpoint,label)

if ((${#ListPart[@]} == 0)); then
  err "Il n’y a pas de partition susceptible d’être montée."
  exit 2
fi

nbDev=$(("${#ListPart[@]}"/5))

          echo             # 0        1           2             3             4
          echo "  n°  ⇒    path     fstype  externe/interne     mountpoint     label"
echo -e "\\033[0;33m ----------------------------------------------------------------------------- \\033[0;0m"
for (( n=0; n<nbDev; n++ )); do
  if ((n+1 < 10)); then
    echo "  $((n+1))   ⇒ ${ListPart[$n,0]}    ${ListPart[$n,1]}          ${ListPart[$n,2]}       ${ListPart[$n,3]}      ${ListPart[$n,4]}"
  else
    echo "  $((n+1))  ⇒ ${ListPart[$n,0]}    ${ListPart[$n,1]}          ${ListPart[$n,2]}       ${ListPart[$n,3]}      ${ListPart[$n,4]}"
  fi
done
echo

while test -z "$PartNum"; do
  read -rp "Choisissez le numéro correspondant à votre future partition de données : " PartNum
  if ! [[ $PartNum =~ ^[1-9][0-9]*$ ]] || ! ((PartNum > 0 && PartNum <= nbDev)); then
    err "Votre choix doit être un nombre entier compris entre 1 et $nbDev."
    unset PartNum
  fi
done

Part="${ListPart[$((PartNum-1)),0]}"
PartFstype="${ListPart[$((PartNum-1)),1]}"
PartPlug="${ListPart[$((PartNum-1)),2]}"
PartLabel="${ListPart[$((PartNum-1)),4]}"

blue "Votre choix : $PartNum = « $Part »"

if test -z "$PartLabel";then
  echo "La partition « $Part » n’a pas d’étiquette."
  chooseLabel
else
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  checkLabel "$PartLabel"
  if (( $? == 1 )); then
    err "Étiquette invalide !"
    unset newLabel
    chooseLabel
  else
    while true; do
      read -rp "Voulez-vous changer l’étiquette de la partition « $Part » ? [O/n] "
      case "$REPLY" in
        N|n)
          blue "Votre choix : non"
          newLabel="$PartLabel"
          break
        ;;
        Y|y|O|o|"")
          blue "Votre choix : oui"
          chooseLabel
          break
        ;;
        *) err "Choix invalide";;
      esac
    done
  fi
fi

while true; do
  read -rp "Voulez-vous procéder au montage maintenant pour la partition « $Part » en y mettant pour étiquette « $newLabel » dans le dossier « $Mount » ? [O/n] "
  case "$REPLY" in
    N|n)
      err "Annulation par l’utilisateur !"
      exit 0
    ;;
    Y|y|O|o|"")
      blue "Votre choix : oui"
      if grep -q "$(lsblk -no uuid "$Part")" /etc/fstab; then
        info "L’UUID de la partition est déjà présent dans le fstab !"
        q=1
      elif grep -Eq "(LABEL=|/dev/disk/by-label/)$newLabel([[:space:]])" /etc/fstab; then
        info "L’étiquette « $newLabel » est déjà utilisée dans le fstab !"
        q=1
      elif grep -q "^$Part" /etc/mtab; then
        info "La partition « $Part » est déjà montée !"
        q=1
      fi

      sav_file "/etc/fstab"
      log_file "/etc/fstab" "b"

      while (("$q" == 1)); do
        echo "Le fichier « /etc/fstab » sera mis à jour si vous poursuivez"
        read -rp "Etes-vous SÛR de vouloir procéder au montage pour la partition « $Part » en y mettant pour étiquette « $newLabel » ? [O/n] "
        case "$REPLY" in
          N|n)
            err "Annulation par l’utilisateur !"
            exit 0
          ;;
          Y|y|O|o|"")
            blue "Votre choix : oui"
            # nettoyage
            if test "$do_change" = "yes"; then
              # traitement des partitions montées
              mapfile -t mountedParts < <(grep -E "$Part"[[:space:]] /etc/mtab | cut -d ' ' -f 2)
              # traitement des partitions NON montées
              mapfile -t unmountedParts < <(awk '/^(LABEL=|\/dev\/disk\/by-label\/)'$PartLabel'([[:space:]])/{print $2}' /etc/fstab)
              delMountPoints mountedParts unmountedParts
              sed -i "/$(lsblk -no uuid "$Part")/d" /etc/fstab
              sleep 1 # Prise en compte du montage par le dash, sans délai, parfois la partition ne s’affiche pas.
            fi
            break
          ;;
          *) err "Choix invalide";;
        esac
      done

      if test "$do_change" = "yes"; then
        # construction des éléments :
        if [[ $PartFstype =~ ^ext[2-4] ]]; then
          e2label "$Part" "$newLabel"
          if ((PartPlug == 0)); then # partition interne
            echo "LABEL=$newLabel $Mount/$newLabel $PartFstype defaults" | tee -a /etc/fstab
          else # partition externe EXT2/3/4
            echo "LABEL=$newLabel $Mount/$newLabel $PartFstype defaults,nofail,x-systemd.device-timeout=1" | tee -a /etc/fstab
          fi
        elif test "$PartFstype" = "ntfs"; then
          ntfslabel  "$Part" "$newLabel"
          if ((PartPlug == 0)); then # partition interne
            if dpkg-query -l ntfs-3g | grep -q "^[hi]i"; then
              echo "LABEL=$newLabel $Mount/$newLabel ntfs-3g defaults,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" | tee -a /etc/fstab
            else
              echo "LABEL=$newLabel $Mount/$newLabel ntfs defaults,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" | tee -a /etc/fstab
            fi
          else # partition externe NTFS
            if dpkg-query -l ntfs-3g | grep -q "^[hi]i"; then
              echo "LABEL=$newLabel $Mount/$newLabel ntfs-3g defaults,nofail,x-systemd.device-timeout=1,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" | tee -a /etc/fstab
            else
              echo "LABEL=$newLabel $Mount/$newLabel ntfs defaults,nofail,x-systemd.device-timeout=1,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" | tee -a /etc/fstab
            fi
          fi
        fi
        log_file "/etc/fstab" "a"

        part_data_path="$Mount/$newLabel"
        ! test -d "$part_data_path" && mkdir -v "$part_data_path"
        systemctl daemon-reload
        if ! mount -a || test -z "$(grep -E ^LABEL="$newLabel"[[:space:]] /etc/fstab)"; then
          err "Inattendue , annulation des modifications !"
          mv -v /etc/fstab.BaK"$now_time" /etc/fstab # il faut enlever la ligne qui a étée ajouter au fstab
          systemctl daemon-reload
          sleep 1
          umount -v "$part_data_path"
          rmdir -v "$part_data_path"
          exit 3
        fi

        part_data_user_dir="$Mount/$newLabel/$SUDO_USER-$newLabel"
        ! test -d "$part_data_user_dir" && mkdir -v "$part_data_user_dir"
        chown -c "$SUDO_USER": "$part_data_user_dir"

        trash_user_dir="$part_data_path"/.Trash-"$SUDO_UID"
        ! test -d "$trash_user_dir" && mkdir -v "$trash_user_dir"
        chown -c "$SUDO_USER": "$trash_user_dir"
        chmod -c 700 "$trash_user_dir"

        if test -d "$trash_user_dir"; then
          echo
          info "Création de la corbeille réussie"
          echo
          blue "Vous pouvez maintenant accéder à votre partition en parcourant le dossier suivant : « $part_data_user_dir »."
          echo
          info "Fin montage partition « $Part » avec l'étiquette « $newLabel »."
          echo
          echo -e "\\033[0;33m ----------------------------------------------------------------------------- \\033[0;0m"
        else
          err "Inconnue !"
          exit 4
        fi
      else # mode test :
        part_data_user_dir="$Mount/$newLabel/$SUDO_USER-$newLabel"
        echo -e "\\033[0;33m ----------------------------------------------------------------------------- \\033[0;0m"
        echo
        blue "Vous pouvez maintenant accéder à votre partition en parcourant le dossier suivant : « $part_data_user_dir » ."
        echo
      fi
      break
    ;;
    *) err "Choix invalide";;
  esac
done

while true; do
  read -rp "Voulez-vous déplacer TOUTES vos données utilisateur dans la partition « $Part » qui vient d'être montée sur : « $part_data_user_dir » ?
  cette action peut durer très longtemps, ne pas interrompre pour éviter la perte des données . soyez patient svp !
  Lancer le déplacement des données maintenant ?  [O/n]"
  case "$REPLY" in
    N|n)
      err "Annulation par l’utilisateur !"
      exit 0
    ;;
    Y|y|O|o|"")
      blue "Votre choix : oui"
      break
    ;;
    *) err "Choix invalide";;
  esac
done

while true; do
  read -rp "Pour intégrer le déplacement de vos données au sein du système :
  Répondez « 1 » pour utiliser les variables XDG seulement.
  Répondez « 2 » pour utiliser les liens symboliques seulement.
  Répondez « 3 » pour utiliser les variables XDG ET les liens symboliques.
  Répondez « A » pour abandonner.

  NOTE : l'utilisation des liens symboliques est à éviter et n'est pas conseillée si vous ne connaissez pas leur fonctionnement et ce que cela implique !

  choix : [ 1 / 2 / 3 / A ] ?"
  case "$REPLY" in
    1)
      blue "Votre choix ( conseillé ) : les variables XDG uniquement"
      break
    ;;
    2)
      info "Votre choix ( dé-conseillé ) : les liens symboliques uniquement"
      break
    ;;
    3)
      info "Votre choix ( dé-conseillé ) : les variable XDG + les liens symboliques"
      break
    ;;
    A)
      err "Annulation par l’utilisateur !"
      exit 0
    ;;
    *) err "Choix invalide";;
  esac
done

xdg_conf_file="$home/.config/user-dirs.dirs"
sav_file "$xdg_conf_file" "u"
log_file "$xdg_conf_file" "b"
gnome_book_file="$home/.config/gtk-3.0/bookmarks"
sav_file "$gnome_book_file" "u"
log_file "$gnome_book_file" "b"
qt_book_file="$home/.local/share/user-places.xbel"
sav_file "$qt_book_file" "u"
log_file "$qt_book_file" "b"


# creer un lien pour chaque dossier déplacé :
info "Déplacement des dossiers : \n"
for elem in "$home"/*; do
  if test -d "$elem"; then
    dir_name=${elem##*/}
    dir_tab+=( "$dir_name" )
    if [[ "$dir_name" =~ ^\. ]] || test "$dir_name" = "snap" -o "$dir_name" = "thunderbird.tmp"; then echo " ! Dossier système , à ne pas déplacer : $dir_name !"; continue;fi
    if test -L "$elem"; then echo "  ! $dir_name est un lien , pas de déplacement ."; continue;fi
    # déplacement des dossiers
    echo "Déplacement du dossier « $dir_name » en cours ..."
    if test "$do_change" = "yes"; then
      if test "$REPLY" = "1"; then
        sudo -u "$SUDO_USER" mv "$elem" "$part_data_user_dir"
      else
        sudo -u "$SUDO_USER" mv "$elem" "$part_data_user_dir" && sudo -u "$SUDO_USER" ln -s "$part_data_user_dir/$dir_name" "$home"
      fi
      if (( $? != 0)); then
        err "Copie non effectuée !"
        exit 1
      fi
    fi
  fi
done

printf "\n"
info "Modifications des variables XDG et des marque-pages :"
printf "\n"

for dir_name in "${dir_tab[@]}"; do
  enco_dir=$(urlencode "$dir_name")
  # traitement XDG
  if test "$REPLY" != "2"; then
    if test -f "$xdg_conf_file"; then
      # récupération des éléments
      xdg_var_name="$(awk -F'[="]' -v pattern="$dir_name" '/^XDG/ && $3 ~ pattern {sub(/XDG_/,"",$1); sub(/_DIR/,"",$1); print $1}' "$xdg_conf_file")"
      mapfile -t numLines < <(grep -En "/$dir_name\"([[:space:]]|$)" "$xdg_conf_file" | cut -d ":" -f 1 | sort -rn)
      # suppression ancienne config
      if ((${#numLines[@]} > 0)); then
        for num in "${numLines[@]}"; do
          echo "Suppression de la ligne « ${num} » dans le fichier « $xdg_conf_file »"
          test "$do_change" = "yes" && sudo -u "$SUDO_USER" sed -i "${num}d" "$xdg_conf_file"
        done
      fi
      # Construction des éléments :
      if test -n "$xdg_var_name"; then
        echo "Modification de la variable : « $xdg_var_name » => $part_data_user_dir/$dir_name"
        test "$do_change" = "yes" && sudo -u "$SUDO_USER" xdg-user-dirs-update --set "$xdg_var_name"  "$part_data_user_dir/$dir_name"
      else
        info "Pas de modification de la variable XDG pour le dossier « $dir_name »"
      fi
    else # FIN XDG
      err "Pas de fichier .config/user-dirs.dirs !"
    fi
  fi

  # traitement bookmarks
  if test -f "$gnome_book_file"; then # GNOME
    mapfile -t numLines < <(grep -En "/$enco_dir([[:space:]]|$)" "$gnome_book_file" | cut -d ":" -f 1 | sort -rn)
    if ((${#numLines[@]} > 0)); then
      for num in "${numLines[@]}"; do
        # suppression ancienne config
        echo "Suppression de la ligne « ${num} » dans le fichier « $gnome_book_file »"
        test "$do_change" = "yes" && sudo -u "$SUDO_USER" sed -i "${num}d" "$gnome_book_file"
      done
      # Construction des éléments :
      echo "Modification du marque-pages : « file://$part_data_user_dir/$enco_dir $dir_name » pour GNOME bookmarks"
      test "$do_change" = "yes" && sudo -u "$SUDO_USER" echo "file://$part_data_user_dir/$enco_dir $dir_name" | tee -a "$gnome_book_file"
    else
      info "Pas de modification de marque-pages GNOME a effectuer pour le dossier « $dir_name »"
    fi
  else # FIN bookmarks GNOME
    info "pas de fichier « $gnome_book_file » a traiter !"
  fi

  if test -f "$qt_book_file"; then # QT
    # install xmlstarlet :
    if ! dpkg-query -f '${binary:Package}\n' -W "xmlstarlet" &>/dev/null; then
      apt-get install -qq "xmlstarlet"
    fi

    book_found="$(grep "$home/$enco_dir" "$qt_book_file")"
    if test -z "$book_found"; then
      info "Pas de modification de marque-pages QT a effectuer pour le dossier « $dir_name »"
    else
      echo "Modification du marque-pages : « file://$part_data_user_dir/$enco_dir $dir_name » pour QT bookmarks"
      test "$do_change" = "yes" && sudo -u "$SUDO_USER" xmlstarlet ed -L -N xmlns:bookmark='http://www.freedesktop.org/standards/desktop-bookmarks' -u "//bookmark[@href='file://$home/$enco_dir']/@href" -v "file://$part_data_user_dir/$enco_dir" "$qt_book_file"
    fi
  else # FIN bookmarks QT
    info "Pas de fichier « $qt_book_file » a traiter !"
  fi
done

test -f "$gnome_book_file" && sudo -u "$SUDO_USER" sort -t' ' +1 -d "$gnome_book_file" -o "$gnome_book_file" # trie les bookmarks par ordre alphabetique
log_file "$xdg_conf_file" "a"
log_file "$gnome_book_file" "a"
log_file "$qt_book_file" "a"
if test "$do_change" = "yes"; then
  sudo -u "$SUDO_USER" echo -e "état du home APRES modifs :" | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
  sudo -u "$SUDO_USER" ls -l  | sudo -u "$SUDO_USER" tee -a "$log" > /dev/null
fi
echo
test "$do_change" = "yes" && info "pour voir l'état des fichiers modifiés passer la commande suivante : cat automount.log$now_time"
echo
blue "Script pour montage de partition de données terminé avec succès !"
echo
echo -e "\\033[0;33m ----------------------------------------------------------------------------- \\033[0;0m"
echo
info "Vous devez relancer la session graphique ou redémarrer l ' ordinateur pour que les changements soient effectifs."
echo -e "\\033[1;31m ! IMPORTANT ! : Toutes vos données utilisateurs seront dorénavant stockées dans votre partition $newLabel : « $Part » .
Ces données sont accessibles par le chemin suivant : « $part_data_path ».
Pour SAUVEGARDER vos données personnelles , vous devez dorénavant utiliser le nouveau chemin de stockage de vos données personnelles : « $part_data_user_dir ».
Voir ce lien pour plus d'infos sur la sauvegarde : https://doc.ubuntu-fr.org/sauvegarde \\033[0;0m"
