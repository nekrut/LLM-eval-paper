#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
OUTDIR=results

mkdir -p "$OUTDIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" || ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    # Skip if final artifact exists
    if [[ -f "${OUTDIR}/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi

    R1=data/raw/${sample}_1.fq.gz
    R2=data/raw/${sample}_2.fq.gz
    BAM=${OUTDIR}/${sample}.bam
    VCF=${OUTDIR}/${sample}.vcf

    # Alignment and sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling
    if [[ ! -f "$VCF" && ! -f "${VCF}.gz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    fi

    # VCF compression and indexing
    if [[ ! -f "${VCF}.gz" ]]; then
        bgzip -c "$VCF" > "${VCF}.gz"
        tabix -p vcf "${VCF}.gz"
        rm -f "$VCF"
    fi
done

# Collapse step (idempotent, rebuild if any input VCF is newer)
COLLAPSED=${OUTDIR}/collapsed.tsv
REBUILD_COLLAPSED=0
if [[ ! -f "$COLLAPSED" ]]; then
    REBUILD_COLLAPSED=1
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${OUTDIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            REBUILD_COLLAPSED=1
            break
        fi
    done
fi

if [[ "$REBUILD_COLLAPSED" -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUTDIR}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi