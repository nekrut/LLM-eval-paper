#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# 2. Reference indexing (once)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# 3-5. Per-sample alignment, sorting, and indexing
for SAMPLE in "${SAMPLES[@]}"; do
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    FASTQ1="${RAW}/${SAMPLE}_1.fq.gz"
    FASTQ2="${RAW}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"
    VCF="${RESULTS}/${SAMPLE}.vcf"

    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" -R "$RG" "$REF" "$FASTQ1" "$FASTQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq
    if [[ ! -f "${VCF}.gz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    fi

    # 7. VCF compression and indexing
    if [[ ! -f "${VCF}.gz.tbi" ]]; then
        bgzip -c "$VCF" > "${VCF}.gz"
        tabix -p vcf "${VCF}.gz"
        rm -f "$VCF"
    fi
done

# 8. Collapse step
COLLAPSED="${RESULTS}/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [[ ! -f "$COLLAPSED" ]] || [[ "$COLLAPSED" -ot "${RESULTS}/${SAMPLES[0]}.vcf.gz" ]]; then
    {
        echo "$HEADER"
        for SAMPLE in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS}/${SAMPLE}.vcf.gz"
        done
    } > "$COLLAPSED"
fi