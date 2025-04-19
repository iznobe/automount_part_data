#!/bin/bash

# ----------------------------------------------------------------------------
# "LICENCE BEERWARE" (Révision 42):
# <iznobe@forum.ubuntu-fr.org> a créé ce fichier. Tant que vous conservez cet avertissement,
# vous pouvez faire ce que vous voulez de ce truc. Si on se rencontre un jour et
# que vous pensez que ce truc vaut le coup, vous pouvez me payer une bière en
# retour.
# ----------------------------------------------------------------------------

label() {
  local rgx="[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]"

  while [ -z "$Label" ]; do
    read -rp "Choisissez l’étiquette (LABEL) de votre partition de données, elle doit être UNIQUE et ne pas contenir d’espace, d’accent, de caractères spéciaux et au maximum 16 caractères : " Label
    if [[ "$Label" =~ $rgx || "${#Label}" -gt 16 ]]; then
      echo "Le nom de votre étiquette comporte une espace, un accent ou un caractère spécial ou plus de 16 caractères !"
      unset Label
    fi
  done
  for (( n=0; n<"$nbDev"; n++ )); do
    if [[ $Label == "${ListPart[$n,3]}" ]]; then
      echo "Erreur, votre étiquette « $Label » est déjà attribuée !"
      exit 4
    fi
  done
}

unmount() {
  local rgx="^(/mnt/|/media/).+$"

  while [ -z "$rep3" ]; do
    read -rp "Voulez-vous démonter la partition « $Part » de son emplacement actuel et procéder aux changements pour la monter avec l'étiquette « $Label » ? [O/n] " Rep3
    case "$Rep3" in
      N|n)
        echo "Annulation par l’utilisateur !"
        unset Rep3
        exit 0
      ;;
      Y|y|O|o|"")
        PartMountPoints=( $(grep "$Part" /etc/mtab | cut -d " " -f 2) )
        for pmp in "${PartMountPoints[@]}"; do
          umount -v "$pmp"
          if [[ "$pmp" =~ $rgx ]]; then
            rmdir -v "$pmp"
          else
            echo "$pmp n’a pas été supprimé."
          fi
          numLines=( $(grep -n "$pmp" /etc/fstab | cut -d ":" -f 1 | sort -rn) )
          for n in "${numLines[@]}"; do
            sed -i "${n}d" /etc/fstab
          done
        done
        sleep 1 # Prise en compte du montage par le dash, sans délai, parfois la partition ne s’affiche pas.
        unset Rep3
        break
      ;;
      *)
        unset Rep3
      ;;
    esac
 done
}

if ((UID)); then
  echo "Vous devez être super utilisateur pour lancer ce script (essayez avec « sudo »)"
  exit 1
fi

$(lsblk -no path,fstype,mountpoint,label |
awk -v i=-1 'BEGIN { print "declare -A ListPart" } 
$2 ~ "^(ext[2-4]|ntfs)$" {
  if ($3 ~ "^(/|/boot|/home|/tmp|/usr|/var|/srv|/opt|/usr/local)$") {
    next  
  }
  else if ($3 ~ "^/") {
    print "ListPart["++i",0]="$1"\nListPart["i",1]="$2\
    "\nListPart["i",2]="$3"\nListPart["i",3]="$4
  }
  else {
    print "ListPart["++i",0]="$1"\nListPart["i",1]="$2\
    "\nListPart["i",2]=\nListPart["i",3]="$3
  }
}')

if [ "${#ListPart[@]}" == "0" ]; then
  echo "Il n’y a pas de partition susceptible d’être montée."
  exit 8
fi

nbDev=$(("${#ListPart[@]}"/4))

echo
echo "n° ⇒  path   label   fstype   mountpoint"
echo "----------------------------------------"
for (( n=0; n<nbDev; n++ )); do
  echo "$((n+1)) ⇒ ${ListPart[$n,0]}   ${ListPart[$n,3]}   ${ListPart[$n,1]}   ${ListPart[$n,2]}"
done
echo

while [ -z "$PartNum" ]; do
  read -rp "Choisissez le numéro correspondant à votre future partition de données : " PartNum
  if [[ ! "$PartNum" =~ ^[1-9][0-9]*$ ]] || ! (( PartNum > 0 && PartNum <= nbDev )); then
    echo "Votre choix doit être un nombre entier compris entre 1 et $nbDev."
    unset PartNum
  fi
done

Part="${ListPart[$((PartNum-1)),0]}"
PartLabel="${ListPart[$((PartNum-1)),3]}"
PartFstype="${ListPart[$((PartNum-1)),1]}"

if [[ -z "$PartLabel" ]]; then
  echo "La partition « $Part » n’a pas d’étiquette."
  label
else
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  while [ -z "$Rep" ]; do
    read -rp "Voulez-vous changer l’étiquette de la partition « $Part » ? [O/n] " Rep
    case "$Rep" in
      N|n)
        Label="$PartLabel"
        unset Rep
        break
      ;;
      Y|y|O|o|"")
        label
        unset Rep
        break
      ;;
      *)
        unset Rep
      ;;
    esac
  done
fi

while [ -z "$Rep2" ]; do
  read -rp "Voulez-vous procéder au montage maintenant pour la partition « $Part » en y mettant pour étiquette « $Label » ? [O/n] " Rep2

  case "$Rep2" in
    N|n)
      echo "Annulation par l’utilisateur !"
      unset Rep2
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
      if [[ "$PartFstype" =~ ext[2-4] ]]; then
        e2label "$Part" "$Label"
        echo "LABEL=$Label /media/$Label $PartFstype defaults,nofail,x-systemd.device-timeout=1" >> /etc/fstab
      elif [[ "$PartFstype" == "ntfs"  ]]; then
        ntfslabel  "$Part" "$Label"
        echo "LABEL=$Label /media/$Label ntfs3 defaults,nofail,x-systemd.device-timeout=1,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" >> /etc/fstab
      fi
      mkdir /media/"$Label" 2>/dev/null
      systemctl daemon-reload
      mount -a 2>/dev/null

      mkdir /media/"$Label"/"$SUDO_USER"-"$Label" 2>/dev/null
      chown "$SUDO_USER": /media/"$Label"/"$SUDO_USER"-"$Label" 2>/dev/null
      mkdir /media/"$Label"/.Trash-"$SUDO_UID" 2>/dev/null
      chown "$SUDO_USER": /media/"$Label"/.Trash-"$SUDO_UID" 2>/dev/null
      chmod 700 /media/"$Label"/.Trash-"$SUDO_UID" 2>/dev/null

      if [ -e /media/"$Label"/.Trash-"$SUDO_UID" ]; then
        echo "-----------------------------------------------------------------"
        echo "Script pour montage de partition de données terminé avec succès !"
        echo ""
        echo "Vous pouvez maintenant accéder à votre partition en parcourant le dossier suivant : « /media/$Label/$SUDO_USER-$Label »."
      else
        echo "erreur inconnue !"
        exit 10
      fi
      unset Rep2
      break
    ;;
    *)
      unset Rep2
    ;;
  esac
done
