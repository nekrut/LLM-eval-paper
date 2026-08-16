#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Check if all outputs exist
all_present=true
for s in "${SAMPLES[@]}"; do
    for f in bam bai vcf.gz tbi; do
        [ ! -f "results/${s}.${f}" ] && all_present=false
    done
done
if $all_present && [ -f results/collapsed.tsv ]; then
    exit 0
fi

# Index reference if needed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

for s in "${SAMPLES[@]}"; do
    bam="results/${s}.bam"
    bai="results/${s}.bai"
    vcf="results/${s}.vcf.gz"
    tbi="results/${s}.tbi"

    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf" ] && [ -f "$tbi" ]; then
        continue
    fi

    fq1="data/raw/${s}_1.fq.gz"
    fq2="data/raw/${s}_2.fq.gz"

    bwa mem -t $THREADS data/ref/chrM.fa "$fq1" "$fq2" | samtools view -Sb - | samtools sort -@ $THREADS -o "$bam"
    samtools index "$bam"
    lofreq vcfout "$bam" --threads $THREADS -o "$vcf"
    tabix -p vcf "$vcf"
done

tmpfile=$(mktemp)
for s in "${SAMPLES[@]}"; do
    vcf="results/${s}.vcf.gz"
    bcftools view "$vcf" | awk -v sample="$s" '
        BEGIN{OFS="\t"}
        /^#/ {next}
        {
            split($8,info,";")
            af=""
            for(i in info){
                if(info[i] ~ /^AF=/){af=substr(info[i],4)}
            }
            n1 = split($5,alts,",")
            n2 = split(af,afs,",")
            for(j=1;j<=n1;j++){
                print sample,$1,$2,$4,alts[j],afs[j]
            }
        }' >> "$tmpfile"
done
printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
cat "$tmpfile" >> results/collapsed.tsv
rm "$tmpfile"

exit 0