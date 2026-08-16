#!/usr/bin/env bash
set -euo pipefail

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# Exit if all expected outputs already exist
all_present=true
for s in "${samples[@]}"; do
    for ext in ".bam" ".bai" ".vcf.gz" ".vcf.gz.tbi"; do
        if [[ ! -e "results/${s}${ext}" ]]; then
            all_present=false
            break 2
        fi
    done
done

if $all_present; then
    exit 0
fi

# Index reference if needed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fa.fai" ]]; then
    samtools faidx "$REF"
fi

for s in "${samples[@]}"; do
    bam="results/${s}.bam"
    bai="results/${s}.bai"
    vcf="results/${s}.vcf.gz"
    tbi="results/${s}.vcf.gz.tbi"

    if [[ -e "$bam" && -e "$bai" && -e "$vcf" && -e "$tbi" ]]; then
        continue
    fi

    fq1="data/raw/${s}_1.fq.gz"
    fq2="data/raw/${s}_2.fq.gz"

    bwa mem -t 4 "$REF" "$fq1" "$fq2" | \
    samtools view -bS - | \
    samtools sort -@ 4 -o "$bam"

    samtools index "$bam"

    lofreq call -f "$REF" "$bam" | bgzip > "$vcf"
    tabix -p vcf "$vcf"
done

# Generate collapsed.tsv
collapsed="results/collapsed.tsv"
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
for s in "${samples[@]}"; do
    vcf="results/${s}.vcf.gz"
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$vcf" >> "$collapsed"
done

exit 0