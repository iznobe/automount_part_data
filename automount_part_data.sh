#!/bin/bash

# ----------------------------------------------------------------------------
# "LICENCE BEERWARE" (Révision 42):
# <iznobe@forum.ubuntu-fr.org> a créé ce fichier. Tant que vous conservez cet avertissement,
# vous pouvez faire ce que vous voulez de ce truc. Si on se rencontre un jour et
# que vous pensez que ce truc vaut le coup, vous pouvez me payer une bière en
# retour.
# ----------------------------------------------------------------------------

LC_ALL=C
checkLabel () {
local rgx="[^[:alnum:]_.-]"
#local rgx="[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-]"
(( $#==1 )) && newLabel="$1"
if [[ $newLabel =~ $rgx || ${#newLabel} -gt 16 ]]; then
    err "Le nom de votre étiquette comporte une espace, un accent ou un caractère spécial ou plus de 16 caractères !"
    unset newLabel
    return 1
fi
if test -z "$1"; then
  for i in ${!ListPart[*]}; do
    if [[ $i == *,3 && ${ListPart[$i]} == "$newLabel" ]]; then
      err "votre étiquette « $newLabel » est déjà attribuée ! Choisissez-en une autre."
      unset newLabel
      break
    fi
  done
fi

}

chooseLabel() {
  while [ -z "$newLabel" ]; do
    read -rp "Choisissez l’étiquette (LABEL) de votre partition de données, elle doit être UNIQUE et ne pas contenir d’espace, d’accent, de caractères spéciaux et au maximum 16 caractères : " newLabel
    checkLabel
  done
}

delMountPoints() {
    local rgx="^(/mnt/|/media/).+$"
    declare -n parts=$1
    for part in "${parts[@]}"; do
        if test "$1" = 'mountedParts'; then umount -v "$part"; fi
        if [ -d "$part" ]; then
            if [[ $part =~ $rgx ]]; then
                rmdir -v "$part"
            else
                echo "$part a été conservé."
            fi
        fi
        mapfile -t numLines < <(grep -n "$part" /etc/fstab | cut -d ":" -f 1 | sort -rn)
        for n in "${numLines[@]}"; do
            sed -i "${n}d" /etc/fstab
        done
    done
}

err() {
    >&2 echo -e "\\033[1;31m Erreur : $* \\033[0;0m"
}

if ((UID)); then
  err "Vous devez être super utilisateur pour lancer ce script (essayez avec « sudo $0 »)."
  exit 1
fi

declare -A ListPart
declare -A Rgx=( [fstype]="^(ext[2-4]|ntfs)" [mountP]="^(/|/boot|/home|/tmp|/usr|/var|/srv|/opt|/usr/local)$" )

i=-1

while read -ra lsblkDT; do #path fstype mountpoint label
  if [[ ${lsblkDT[1]} =~ ${Rgx[fstype]} ]]; then
    if [[ ${lsblkDT[2]} =~ ${Rgx[mountP]} ]]; then
      continue
    else
      ((++i))
      ListPart[$i,0]="${lsblkDT[0]}"
      ListPart[$i,1]="${lsblkDT[1]}"
      if [[ ${lsblkDT[2]} =~ ^/ ]]; then
        ListPart[$i,2]="${lsblkDT[2]}"
        ListPart[$i,3]="${lsblkDT[3]}"
      else
        ListPart[$i,2]=""
        ListPart[$i,3]="${lsblkDT[2]}"
      fi
    fi
  fi
done < <(lsblk -no path,fstype,mountpoint,label)

if ((${#ListPart[@]} == 0)); then
  echo "Il n’y a pas de partition susceptible d’être montée."
  exit 2
fi

nbDev=$(("${#ListPart[@]}"/4))

echo
echo "  n°  ⇒    path     label     fstype     mountpoint"
echo "-----------------------------------------------------------------"
for (( n=0; n<nbDev; n++ )); do
  if ((n+1 < 10)); then
    echo " $((n+1))  ⇒ ${ListPart[$n,0]}   ${ListPart[$n,3]}   ${ListPart[$n,1]}   ${ListPart[$n,2]}"
  else
    echo " $((n+1)) ⇒ ${ListPart[$n,0]}   ${ListPart[$n,3]}   ${ListPart[$n,1]}   ${ListPart[$n,2]}"
  fi
done
echo

while [ -z "$PartNum" ]; do
  read -rp "Choisissez le numéro correspondant à votre future partition de données : " PartNum
  if ! [[ $PartNum =~ ^[1-9][0-9]*$ ]] || ! ((PartNum > 0 && PartNum <= nbDev)); then
    err "Votre choix doit être un nombre entier compris entre 1 et $nbDev."
    unset PartNum
  fi
done

Part="${ListPart[$((PartNum-1)),0]}"
PartLabel="${ListPart[$((PartNum-1)),3]}"
PartFstype="${ListPart[$((PartNum-1)),1]}"

checkLabel "$PartLabel"
if (( $? == 1 )); then
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  err "étiquette incorrecte ! vous devez choisir une étiquette valide."
  unset newLabel
  chooseLabel
elif test -z "$PartLabel";then
  echo "La partition « $Part » n’a pas d’étiquette."
  chooseLabel
else
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  while true; do
    read -rp "Voulez-vous changer l’étiquette de la partition « $Part » ? [O/n] "
    case "$REPLY" in
      N|n)
        newLabel="$PartLabel"
        break
      ;;
      Y|y|O|o|"")
        chooseLabel
        break
      ;;
      *)
      ;;
    esac
  done
fi

while true; do
  read -rp "Voulez-vous procéder au montage maintenant pour la partition « $Part » en y mettant pour étiquette « $newLabel » ? [O/n] "

  case "$REPLY" in
    N|n)
      err "Annulation par l’utilisateur !"
      exit 0
    ;;
    Y|y|O|o|"")
      if grep -q "$(lsblk -no uuid "$Part")" /etc/fstab; then
        echo "L’UUID de la partition est déjà présent dans le fstab !"
        echo "les lignes contenant cet UUID seront supprimées du fichier /etc/fstab si vous poursuivez"
        q=1
      elif grep -Eq "(LABEL=|/dev/disk/by-label/)$newLabel" /etc/fstab; then
        echo "L’étiquette « $newLabel » est déjà utilisée dans le fstab !"
        echo "les lignes contenant ce LABEL seront supprimées du fichier /etc/fstab si vous poursuivez"
        q=1
      elif grep -q "^$Part" /etc/mtab; then
        echo "La partition « $Part » est déjà montée !"
        echo "la partition sera demontée , le fichier /etc/fstab nettoyé , et la partition sera à nouveau montée si vous poursuivez"
        q=1
      fi

      while ((q=1)); do
        read -rp "Etes-vous SÛR de vouloir procéder au montage pour la partition « $Part » en y mettant pour étiquette « $newLabel » ? [O/n] "
        case "$REPLY" in
          N|n)
            err "Annulation par l’utilisateur !"
            exit 0
          ;;
          Y|y|O|o|"")
            break
          ;;
          *)
          ;;
        esac
      done

      # sauvegarde
      echo "sauvegarde du fichier « /etc/fstab » en « /etc/fstab.BaK » avant modifications"
      cp /etc/fstab /etc/fstab.BaK

      # nettoyage
      # traitement des partitions montées
      mapfile -t mountedParts < <(grep "$Part" /etc/mtab | cut -d ' ' -f 2)
      delMountPoints mountedParts
      # traitement des partitions NON montées
      mapfile -t unmountedParts < <(grep -E "^(LABEL=|/dev/disk/by-label/)$PartLabel" /etc/fstab | cut -d ' ' -f 2)
      delMountPoints unmountedParts
      sed -i "/$(lsblk -no uuid "$Part")/d" /etc/fstab
      sleep 1 # Prise en compte du montage par le dash, sans délai, parfois la partition ne s’affiche pas.

      # construction des éléments :
      if [[ $PartFstype =~ ext[2-4] ]]; then
        e2label "$Part" "$newLabel"
        echo "LABEL=$newLabel /media/$newLabel $PartFstype defaults,nofail,x-systemd.device-timeout=1" >> /etc/fstab
      elif [ "$PartFstype" == "ntfs" ]; then
        ntfslabel  "$Part" "$newLabel"
        echo "LABEL=$newLabel /media/$newLabel ntfs3 defaults,nofail,x-systemd.device-timeout=1,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" >> /etc/fstab
      fi
      if ! [ -d /media/"$newLabel" ]; then
        mkdir -v /media/"$newLabel"
      fi
      systemctl daemon-reload
      if ! mount -a; then
        err "innatendue , annulation des modifications !"
        umount -v /media/"$newLabel"
        rmdir -v /media/"$newLabel"
        systemctl daemon-reload
        exit 3
      fi

      if ! [ -d /media/"$newLabel"/"$SUDO_USER"-"$newLabel" ]; then
        mkdir -v /media/"$newLabel"/"$SUDO_USER"-"$newLabel"
      fi
      chown -c "$SUDO_USER": /media/"$newLabel"/"$SUDO_USER"-"$newLabel"
      if ! [ -d /media/"$newLabel"/.Trash-"$SUDO_UID" ]; then
        mkdir -v /media/"$newLabel"/.Trash-"$SUDO_UID"
      fi
      chown -c "$SUDO_USER": /media/"$newLabel"/.Trash-"$SUDO_UID"
      chmod -c 700 /media/"$newLabel"/.Trash-"$SUDO_UID"

      if [ -d /media/"$newLabel"/.Trash-"$SUDO_UID" ]; then
        echo
        echo "-----------------------------------------------------------------"
        echo "Script pour montage de partition de données terminé avec succès !"
        echo
        echo "Vous pouvez maintenant accéder à votre partition en parcourant le dossier suivant : « /media/$newLabel/$SUDO_USER-$newLabel »."
        sudo -u "$SUDO_USER" xdg-open "/media/$newLabel/$SUDO_USER-$newLabel" >/dev/null 2>&1
      else
        err "inconnue !"
        exit 4
      fi
      break
    ;;
    *)
    ;;
  esac
done
