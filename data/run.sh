#!/bin/bash

#Plink
zipfile=plink_linux_x86_64_20260927.zip
if [ ! -f $zipfile ]; then
 wget https://s3.amazonaws.com/plink1-assets/${zipfile}
fi

unzip ${zipfile}

# Plink bed file
echo "50003 snp 0.05 0.50 0 0" > sim.txt
./plink --simulate sim.txt --simulate-ncases 49000 --seed 42 --make-bed --out geno

# Generate subsets
nind="2500 10000 50000"
for n in $nind; do 
  head -n $n geno.fam > ind_$n.txt
  ./plink --bfile geno --keep-allele-order --keep ind_$n.txt --make-bed --out geno_$n
done
