#!/bin/bash

# Plink version: PLINK v1.9.0-rc2 64-bit (13 Sep 2026), Linux x86_64 build (plink_linux_x86_64_20260913.zip)

#Plink
if [ ! -f plink_linux_x86_64_20260913.zip ]; then
 wget https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_20260913.zip
fi

unzip plink_linux_x86_64_20260913.zip

export PATH=$(pwd):${HOME}/bin/:$PATH

# Plink bed files
echo "10000 snp 0.05 0.50 0 0" > sim.txt
plink --simulate-qt sim.txt acgt --simulate-n 100000 --seed 42 --make-bed --out source


# Generate samples
nind="2500 10000 20000 30000 40000 50000 60000 70000 80000 90000 100000"
nsnp="1000 2000 3000 4000 5000 6000 7000 8000 9000 10000"

nind="2500 10000"
nsnp="1000 5000"

for n in $nind; do
  head -n $n source.fam | awk '{print $1, $2}' > samples_$n.txt
done

for m in $nsnp; do
  head -n $m source.bim | awk '{print $2}' > snps_$m.txt
done

# Generate subsets
subset() {
  plink --bfile source --keep-allele-order \
    --keep samples_$1.txt --extract snps_$2.txt \
    --make-bed --out n$1_m$2
}

for n in $nind; do 
  subset $n 5000
done

for m in $nsnp; do 
  subset 100000 $m
done

