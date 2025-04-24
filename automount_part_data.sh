#!/bin/bash

# ----------------------------------------------------------------------------
# "LICENCE BEERWARE" (Révision 42):
# <iznobe@forum.ubuntu-fr.org> a créé ce fichier. Tant que vous conservez cet avertissement,
# vous pouvez faire ce que vous voulez de ce truc. Si on se rencontre un jour et
# que vous pensez que ce truc vaut le coup, vous pouvez me payer une bière en
# retour.
# ----------------------------------------------------------------------------

LC_ALL=C

label() {
  local rgx="[^[:alnum:]_-]"

  while [ -z "$Label" ]; do
    read -rp "Choisissez l’étiquette (LABEL) de votre partition de données, elle doit être UNIQUE et ne pas contenir d’espace, d’accent, de caractères spéciaux et au maximum 16 caractères : " Label
    if [[ $Label =~ $rgx || ${#Label} -gt 16 ]]; then
      echo "Le nom de votre étiquette comporte une espace, un accent ou un caractère spécial ou plus de 16 caractères !"
      unset Label
    fi
    if lsblk -no label | grep -q "$Label"; then
      echo "Erreur, votre étiquette « $Label » est déjà attribuée ! Choisissez en une autre."
      unset Label
    fi
  done
}

unmount() {
  local rgx="^(/mnt/|/media/).+$"
  local mp
  mp="$(grep "$Label" /etc/fstab | cut -d ' ' -f 2)"

  while true; do
    read -rp "Voulez-vous démonter la partition « $Part » de son emplacement actuel et procéder aux changements pour la monter avec l'étiquette « $Label » ? [O/n] "
    case "$REPLY" in
      N|n)
        echo "Annulation par l’utilisateur !"
        exit 0
      ;;
      Y|y|O|o|"")
        mapfile -t PartMountPoints < <(grep "$Part" /etc/mtab | cut -d " " -f 2)
        if [ -n "${PartMountPoints[0]}" ]; then
          for pmp in "${PartMountPoints[@]}"; do
            umount -v "$pmp"
            if [[ -d $pmp && $pmp =~ $rgx ]]; then
              rmdir -v "$pmp"
            else
              echo "$pmp n’a pas été supprimé."
            fi
            mapfile -t numLines < <(grep -n "$pmp" /etc/fstab | cut -d ":" -f 1 | sort -rn)
            for n in "${numLines[@]}"; do
              sed -i "${n}d" /etc/fstab
            done
          done
        elif [[ -d $mp && $mp =~ $rgx ]]; then
            rmdir -v "$mp"
        else
          echo "$mp n’a pas été supprimé."
        fi
        sed -i "/$(lsblk -no uuid "$Part")/d" /etc/fstab
        sed -i "/$Label/d" /etc/fstab
        sleep 1 # Prise en compte du montage par le dash, sans délai, parfois la partition ne s’affiche pas.
        break
      ;;
      *)
      ;;
    esac
 done
}

if ((UID)); then
  echo "Vous devez être super utilisateur pour lancer ce script (essayez avec « sudo »)"
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

if (( ${#ListPart[@]} == 0 )); then
  echo "Il n’y a pas de partition susceptible d’être montée."
  exit 2
fi

nbDev=$(("${#ListPart[@]}"/4))

echo
echo " n° ⇒    path    label   fstype   mountpoint"
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
  if [[ ! $PartNum =~ ^[1-9][0-9]*$ ]] || ! (( PartNum > 0 && PartNum <= nbDev )); then
    echo "Votre choix doit être un nombre entier compris entre 1 et $nbDev."
    unset PartNum
  fi
done

Part="${ListPart[$((PartNum-1)),0]}"
PartLabel="${ListPart[$((PartNum-1)),3]}"
PartFstype="${ListPart[$((PartNum-1)),1]}"

if [ -z "$PartLabel" ]; then
  echo "La partition « $Part » n’a pas d’étiquette."
  label
else
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  while true; do
    read -rp "Voulez-vous changer l’étiquette de la partition « $Part » ? [O/n] "
    case "$REPLY" in
      N|n)
        Label="$PartLabel"
        break
      ;;
      Y|y|O|o|"")
        label
        break
      ;;
      *)
      ;;
    esac
  done
fi

while true; do
  read -rp "Voulez-vous procéder au montage maintenant pour la partition « $Part » en y mettant pour étiquette « $Label » ? [O/n] "

  case "$REPLY" in
    N|n)
      echo "Annulation par l’utilisateur !"
      exit 0
    ;;
    Y|y|O|o|"")
      if grep -q "$(lsblk -no uuid "$Part")" /etc/fstab; then
        echo "L’UUID de la partition est déjà présent dans le fstab !"
        unmount        
      elif grep -Eq "(LABEL=|by-label/)$Label" /etc/fstab; then
        echo "L’étiquette « $Label » est déjà utilisée dans le fstab !"
        unmount
      elif grep -q "^$Part" /etc/mtab; then
        echo "La partition « $Part » est déjà montée !"
        unmount
      fi

      # construction des éléments :
      if [[ $PartFstype =~ ext[2-4] ]]; then
        e2label "$Part" "$Label"
        echo "LABEL=$Label /media/$Label $PartFstype defaults,nofail,x-systemd.device-timeout=1" >> /etc/fstab
      elif [ "$PartFstype" == "ntfs" ]; then
        ntfslabel  "$Part" "$Label"
        echo "LABEL=$Label /media/$Label ntfs3 defaults,nofail,x-systemd.device-timeout=1,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" >> /etc/fstab
      fi
      if ! [ -d /media/"$Label" ]; then
        mkdir -v /media/"$Label"
      fi
      systemctl daemon-reload
      if ! mount -a
      then
        exit 4
      fi

      if ! [ -d /media/"$Label"/"$SUDO_USER"-"$Label" ]; then
        mkdir -v /media/"$Label"/"$SUDO_USER"-"$Label"
      fi
      chown -c "$SUDO_USER": /media/"$Label"/"$SUDO_USER"-"$Label"
      if ! [ -d /media/"$Label"/.Trash-"$SUDO_UID" ]; then
        mkdir -v /media/"$Label"/.Trash-"$SUDO_UID"
      fi
      chown -c "$SUDO_USER": /media/"$Label"/.Trash-"$SUDO_UID"
      chmod -c 700 /media/"$Label"/.Trash-"$SUDO_UID"

      if [ -d /media/"$Label"/.Trash-"$SUDO_UID" ]; then
        echo
        echo "-----------------------------------------------------------------"
        echo "Script pour montage de partition de données terminé avec succès !"
        echo
        echo "Vous pouvez maintenant accéder à votre partition en parcourant le dossier suivant : « /media/$Label/$SUDO_USER-$Label »."
      else
        echo "erreur inconnue !"
        exit 5
      fi
      break
    ;;
    *)
    ;;
  esac
done
