#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF="data/ref/chrM.fa"
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ] || [ ! -f "${REF}.ann" ] || [ ! -f "${REF}.bwt" ] || [ ! -f "${REF}.pac" ] || [ ! -f "${REF}.sa" ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    out_bam="results/${sample}.bam"
    out_vcf_gz="results/${sample}.vcf.gz"

    if [ -f "${out_vcf_gz}.tbi" ]; then
        continue
    fi

    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"

    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" "$REF" "$fq1" "$fq2" | \
        samtools sort -@ "$THREADS" -o "$out_bam"

    samtools index -@ "$THREADS" "$out_bam"

    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${sample}.vcf" "$out_bam"

    bgzip -c "${sample}.vcf" > "$out_vcf_gz"
    tabix -p vcf "$out_vcf_gz"
    rm "${sample}.vcf"
done

collapsed="results/collapsed.tsv"
rebuild=false
if [ ! -f "$collapsed" ]; then
    rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        if [ "$(stat -c %Y results/${sample}.vcf.gz)" -gt "$(stat -c %Y "$collapsed")" ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    tmp=$(mktemp)
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" "results/${sample}.vcf.gz" >> "$tmp"
    done
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    cat "$tmp" >> "$collapsed"
    rm "$tmp"
fi

exit 0