#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
OUTDIR=results

mkdir -p "$OUTDIR"

# Step 2: Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Steps 3-7: Per-sample alignment, sorting, indexing, variant calling, compression
for sample in "${SAMPLES[@]}"; do
    bam="${OUTDIR}/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="${OUTDIR}/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip sample if final VCF index exists (implies all prior steps completed)
    if [[ -f "$tbi" ]]; then
        continue
    fi

    # Step 3 & 4: Alignment and sorting
    if [[ ! -f "$bai" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # Step 5: BAM indexing
    if [[ ! -f "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Step 6 & 7: Variant calling, compression, and indexing
    vcf="${OUTDIR}/${sample}.vcf"
    if [[ ! -f "$vcf_gz" ]]; then
        if [[ ! -f "$vcf" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" --verbose \
                --ref "$REF" --out "$vcf" \
                --sig --bonf \
                "$bam"
        fi
        bgzip -c "$vcf" > "$vcf_gz"
        rm -f "$vcf"
    fi

    if [[ ! -f "$tbi" ]]; then
        tabix -p vcf "$vcf_gz"
    fi
done

# Step 8: Collapse to TSV (rebuild only if missing or any input VCF is newer)
TSV="${OUTDIR}/collapsed.tsv"
REBUILD=0
if [[ ! -f "$TSV" ]]; then
    REBUILD=1
else
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${OUTDIR}/${sample}.vcf.gz"
        if [[ "$vcf_gz" -nt "$TSV" ]]; then
            REBUILD=1
            break
        fi
    done
fi

if [[ "$REBUILD" -eq 1 ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${OUTDIR}/${sample}.vcf.gz"
        done
    } > "$TSV"
fi