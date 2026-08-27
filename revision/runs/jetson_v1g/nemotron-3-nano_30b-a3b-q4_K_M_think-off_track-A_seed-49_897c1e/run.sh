#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Step 2: reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

# Step 3-5: per-sample alignment, sorting, indexing
for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    if [[ -f "$bam" && -f "$bai" && -f "$vcf" && -f "$tbi" ]]; then
        continue
    fi

    fastq1=data/raw/${sample}_1.fq.gz
    fastq2=data/raw/${sample}_2.fq.gz

    if [[ ! -f "$fastq1" || ! -f "$fastq2" ]]; then
        echo "FastQ files not found for $sample" >&2
        exit 1
    fi

    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$rg" data/ref/chrM.fa "$fastq1" "$fastq2" |
        samtools sort -@ "$THREADS" -o "$bam"

    samtools index -@ "$THREADS" "$bam"

    lofreq call-parallel --pp-threads "$THREADS" --ref data/ref/chrM.fa \
        --out "$vcf.gz" results/${sample}.bam

    bgzip -c "$vcf.gz" > "$vcf"
    tabix -p vcf "$vcf"

    rm -f "${vcf}.gz"
done

# Step 8: collapse step
collapsed=results/collapsed.tsv
if [[ ! -s "$collapsed" || data/ref/chrM.fa -nt "$collapsed" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            vcf=results/${sample}.vcf.gz
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" >> "$collapsed"
        done
    } > "$collapsed.tmp"
    mv "$collapsed.tmp" "$collapsed"
fi

exit 0