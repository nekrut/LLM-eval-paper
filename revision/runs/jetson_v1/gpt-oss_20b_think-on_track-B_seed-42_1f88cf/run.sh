#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RESULTS_DIR=results
mkdir -p "$RESULTS_DIR"

# Build reference indexes if missing
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="${RESULTS_DIR}/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    if [ -f "$bai" ] && [ -f "$tbi" ]; then
        continue
    fi

    bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
        samtools view -Sb - | samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"

    lofreq call -f "$REF" -m 10 -q 20 -Q 30 -p 0.01 "$bam" |
        bcftools view -O z -o "$vcf_gz"
    tabix "$vcf_gz"
done

collapsed="${RESULTS_DIR}/collapsed.tsv"
if [ ! -f "$collapsed" ]; then
    tmp=$(mktemp)
    for sample in "${samples[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" |
            while IFS= read -r line; do
                printf '%s\t%s\n' "$sample" "$line" >> "$tmp"
            done
    done
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    cat "$tmp" >> "$collapsed"
    rm "$tmp"
fi

exit 0