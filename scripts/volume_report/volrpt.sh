#!/usr/bin/env bash

reuse=false
[[ $1 == "--reuse" ]] && reuse=true

cluster_list_file=cluster.lst
output_csv_file=orphan.csv

status() {
  prefix=$1
  i=$2
  total=$3
  percent=$((200*$i/$total % 2 + 100*$i/$total))
  [[ $i -ne 1 ]] && printf "\r"
  if [[ $i -eq $total ]]; then
    printf "$prefix ... DONE                      \n"
  else
    printf "$prefix ... $i / $total ( $percent%% )"
  fi
}

search_orphan() {
  name=$1

  tmp_csv_file=$name.csv
  tmp_json_file=$name.json

  [[ $reuse != "true" ]] && ibmcloud sl $name volume-list --column id --column notes --column username --column datacenter --column capacity_gb --column bytes_used --column created_by --output JSON > $tmp_json_file
  total=$(jq -r '.[].id' $tmp_json_file | wc -l | tr -d ' ')
  echo "Found $total ${name}s"

  echo > $tmp_csv_file
  i=1
  while read -r id; do
    cluster=; region=; storagename=; datacenter=; capacity_gb=; created_by=; created=; account=; pv=; pvc=; ns=
    status "Searching for orphan ${name}s" $i $total
    eval "$(jq -r ".[] | select(.id == ${id}) | .notes" $tmp_json_file | jq -r '@sh "export cluster=\(.cluster) region=\(.region) pv=\(.pvc) pvc=\(.pvc) ns=\(.ns)"')"
    eval "$(jq -r ".[] | select(.id == ${id}) | \"export storagename=\(.username) datacenter=\(.serviceResource.datacenter.name) capacity_gb=\(.capacityGb) created_by=\(.billingItem.orderItem.order.userRecord.username) created=\(.billingItem.createDate)\""  $tmp_json_file)"
    arrCreateBy=(${created_by//_/ })
    account=${arrCreateBy[0]}
    created_by=${arrCreateBy[1]}
    grep -q $cluster $cluster_list_file || echo "$id, $storagename, $name, $datacenter, $capacity_gb, $created_by, $account, $cluster, $region, $pv, $pvc, $ns" >> $tmp_csv_file
    (( i++ ))
  done < <(jq '.[].id' $tmp_json_file)

  total_orphan=$(cat $tmp_csv_file | wc -l | tr -d ' ')
  percent=$((200*$total_orphan/$total % 2 + 100*$total_orphan/$total))
  echo "Found $total_orphan orphan ${name}s out of $total ( $percent% )"
}

[[ $reuse != "true" ]] && ibmcloud ks clusters --output JSON | jq -r '.[] | select(.state == "normal") | .id' > $cluster_list_file
total_clusters=$(cat $cluster_list_file | wc -l | tr -d ' ')
echo "Found $total_clusters cluster with normal state"

search_orphan "block"
search_orphan "file"

echo -n "ID, Resource Name, Stortage Type, Datacenter, Capacity GB, Created By, From Account, Cluster ID, Region, PV, PVC, Namespace" > $output_csv_file
cat block.csv >> $output_csv_file
cat file.csv  >> $output_csv_file
sed -i "" '/^$/d' $output_csv_file

echo "Final report in file: $output_csv_file"
