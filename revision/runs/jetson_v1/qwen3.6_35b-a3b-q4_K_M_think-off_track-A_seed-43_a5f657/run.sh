#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -f "data/ref/chrM.fa.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"
    vcf="results/${sample}.vcf"

    # 3 & 4. Alignment and sorting (idempotent)
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ] || [ "data/raw/${sample}_2.fq.gz" -nt "$bam" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam" -
    fi

    # 5. BAM indexing (idempotent)
    if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # 6. Variant calling with lofreq (idempotent)
    if [ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_gz" ]; then
        lofreq call-parallel \
            --ref-fa "$REF" \
            --alignments "$bam" \
            --pp-threads $THREADS \
            -o "$vcf" 2>/dev/null
    fi

    # 7. VCF compression and indexing (idempotent)
    if [ ! -f "$tbi" ] || [ "$vcf" -nt "$tbi" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# 8. Collapse step (idempotent)
collapsed="results/collapsed.tsv"
need_rebuild=false
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_rebuild=true
        break
    fi
done

if $need_rebuild; then
    # Should not happen given previous steps, but safety check
    exit 1
fi

# Check if collapsed.tsv needs rebuilding based on timestamps
if [ -f "$collapsed" ]; then
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz.tbi" -nt "$collapsed" ]; then
            need_rebuild=true
            break
        fi
    done
else
    need_rebuild=true
fi

if $need_rebuild; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi