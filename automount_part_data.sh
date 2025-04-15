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
    echo -n "Choisissez l’étiquette (LABEL) de votre partition de données, elle doit être UNIQUE et ne pas contenir d’espace, d’accent, de caractères spéciaux et au maximum 16 caractères : "
    read -r Label
    if [[ "$Label" =~ $rgx || "${#Label}" -gt 16 ]]; then
      echo "Le nom de votre étiquette comporte une espace, un accent ou un caractère spécial ou plus de 16 caractères !"
      unset Label
    fi
  done
  for (( n=0; n<"$nbDev"; n++ )); do # étiquette déjà utilisée ?
    if [[ $Label == "${ListPart[$n,1]}" ]]; then
      echo "Erreur, votre étiquette « $Label » est déjà attribuée !"
      exit 4
    fi
  done
}

if ((UID)); then
  echo "Vous devez être super utilisateur pour lancer ce script (essayez avec « sudo »)"
  exit 0
fi

$(lsblk -no path,label,fstype  |
awk -vi=-1 'BEGIN { print "declare -A ListPart" } \
$NF ~ "ext|ntfs" \
{
j=0 ;
if ($2 ~ /^ext[2-4]$/ || $2 ~ /^ntfs$/)
{ print "ListPart["++i","j"]="$1"\nListPart["i","++j"]=""\nListPart["i","++j"]="$2 }
else
{ print "ListPart["++i","j"]="$1"\nListPart["i","++j"]="$2"\nListPart["i","++j"]="$3 }
}')

nbDev=$(( "${#ListPart[@]}"/3 ))

for (( n=0; n<nbDev; n++ )); do
  echo "$(( n+1 )) ⇒ ${ListPart[$n,0]}   ${ListPart[$n,1]}   ${ListPart[$n,2]}"
done

while [ -z "$PartNum" ]; do
  read -p "Choisissez le numéro correspondant à votre future partition de données : " PartNum
  if [[ ! "$PartNum" =~ ^[1-9][0-9]?$[0-9]?$|^"$nbDev"$ ]]; then # Si la réponse n’est pas un entier positif non nul compris entre 1 et $nbDev ( 1000 maximum )
    echo "Votre choix doit être un nombre entier compris entre 1 et $nbDev."
    unset PartNum
  fi
done

Part="${ListPart[$(( PartNum-1 )),0]}"
PartLabel="${ListPart[$(( PartNum-1 )),1]}"
PartFstype="${ListPart[$(( PartNum-1 )),2]}"

if [[ -z "$PartLabel" ]]; then
  echo "La partition « $Part » n’a pas d’étiquette."
  label
else
  echo "La partition « $Part » a l’étiquette « $PartLabel »."
  while [ -z "$Rep" ]; do
    echo -n "Voulez-vous changer l’étiquette de la partition « $Part » ? [O/n] "
    read -r Rep
    case "$Rep" in
      N|n)
        Label="$PartLabel"
        break
      ;;
      Y|y|O|o|"")
        label
        break
      ;;
      *)
        unset Rep
      ;;
    esac
  done
fi

while [ -z "$Rep2" ]; do
  echo -n "Voulez-vous procéder au montage maintenant pour la partition « $Part » en y mettant pour étiquette « $Label » ? [O/n] "
  read -r Rep2

  case "$Rep2" in
    N|n)
      echo -e "Annulation par l’utilisateur !"
      exit 1
    ;;
    Y|y|O|o|"")
       if grep -q "$Label" /etc/fstab; then # vérifier si une étiquette du même nom existe dans le fstab
        echo -e "L’étiquette « $Label » est déjà utilisée dans le fstab !"
        exit 2
      fi
      if grep -q "$(lsblk -no uuid "$Part")" /etc/fstab; then # PartUUID est déjà present dans fstab
        echo -e "L’UUID de la partition est déjà présent dans le fstab !"
        exit 3
      fi
      if grep -q "^$Part" /etc/mtab; then # vérifier si la partition est déjà montée
        echo -e "La partition « $Part » est déjà montée !"
        while [ -z "$rep3" ]; do
          echo -n "Voulez-vous démonter la partition « $Part » de son emplacement actuel et procéder au changement pour étiquette « $Label » ? [O/n] "
          read -r Rep3
          case "$Rep3" in
            N|n)
              echo -e "Annulation par l’utilisateur !"
              exit 1
            ;;
            Y|y|O|o|"")
              PartMountPoints="$(grep "$Part" /etc/mtab | cut -d " " -f 2)"
              for pmp in "$PartMountPoints"; do
                umount -v "$pmp"
                Num="$(grep -n "$pmp" /etc/fstab | cut -d ":" -f 1 | sort -rV)"
                for n in $Num; do
                  sed -i "${n}d" /etc/fstab
                done
              done
              break
            ;;
            *)
            unset Rep3
            ;;
          esac
        done
      fi

      # construction des éléments :
      if [[ "$PartFstype" =~ ext[2-4] ]]; then
        e2label "$Part" "$Label"
        echo "LABEL=$Label /media/$Label $PartFstype defaults" >> /etc/fstab
      elif [[ "$PartFstype" == "ntfs"  ]]; then
        ntfslabel  "$Part" "$Label"
        echo "LABEL=$Label /media/$Label ntfs3 defaults,nofail,x-gvfs-show,nohidden,uid=$SUDO_UID,gid=$SUDO_GID" >> /etc/fstab
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
      break
    ;;
    *)
      unset Rep2
    ;;
  esac
done

