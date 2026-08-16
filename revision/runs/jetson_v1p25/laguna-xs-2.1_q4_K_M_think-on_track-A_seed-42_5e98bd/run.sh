#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [[ ! -f "data/ref/chrM.fa.$ext" ]]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_uncompressed="results/${sample}.vcf"
    vcf_gz="${vcf_uncompressed}.gz"
    vcf_tbi="${vcf_gz}.tbi"

    # Alignment and sorting
    if [[ ! -f "$bam" ]] || [[ "$(find data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz -print0 | xargs -0 stat -c %Y | sort -nr | head -1)" -gt "$(stat -c %Y "$bam" 2>/dev/null || echo 0)" ]]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            <(zcat "data/raw/${sample}_1.fq.gz") \
            <(zcat "data/raw/${sample}_2.fq.gz") | \
        samtools sort -@ $THREADS -o "$bam"
    fi

    # BAM indexing
    if [[ ! -f "${bam}.bai" ]] || [[ "$(stat -c %Y "$bam")" -gt "$(stat -c %Y "${bam}.bai" 2>/dev/null || echo 0)" ]]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling with lofreq
    if [[ ! -f "$vcf_gz" ]] || [[ "$(stat -c %Y "$bam")" -gt "$(stat -c %Y "$vcf_gz" 2>/dev/null || echo 0)" ]]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"

        # Compress and index VCF
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapsed TSV generation
collapsed="results/collapsed.tsv"
needs_collapse=0

if [[ ! -f "$collapsed" ]]; then
    needs_collapse=1
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [[ "$(stat -c %Y "$vcf_gz")" -gt "$(stat -c %Y "$collapsed" 2>/dev/null || echo 0)" ]]; then
            needs_collapse=1
            break
        fi
    done
fi

if [[ $needs_collapse -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in $SAMPLES; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi

exit 0