#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# --- Step 2: reference indexing (once) ---
if [[ ! -s "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -s "${REF}.amb" || ! -s "${REF}.ann" || ! -s "${REF}.bwt" || ! -s "${REF}.pac" || ! -s "${REF}.sa" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="${RESULTS}/${sample}.bam"
    bai="${RESULTS}/${sample}.bam.bai"
    vcf="${RESULTS}/${sample}.vcf"
    vcfgz="${RESULTS}/${sample}.vcf.gz"
    tbi="${vcfgz}.tbi"

    # --- Steps 3-4: alignment + sort ---
    need_align=1
    if [[ -s "$bam" && "$bam" -nt "$fq1" && "$bam" -nt "$fq2" ]]; then
        need_align=0
    fi
    if [[ "$need_align" -eq 1 ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$fq1" "$fq2" \
            | samtools sort -@ "$THREADS" -o "$bam" -
    fi

    # --- Step 5: BAM indexing ---
    if [[ ! -s "$bai" || "$bai" -ot "$bam" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # --- Steps 6-7: variant calling, compression, indexing ---
    need_call=1
    if [[ -s "$vcfgz" && -s "$tbi" && "$vcfgz" -nt "$bam" && "$tbi" -nt "$vcfgz" ]]; then
        need_call=0
    fi
    if [[ "$need_call" -eq 1 ]]; then
        rm -f "$vcf" "$vcfgz" "$tbi"
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$vcf" \
            "$bam"
        bgzip -f "$vcf"
        tabix -f -p vcf "$vcfgz"
    fi
done

# --- Step 8: collapse step ---
collapsed="${RESULTS}/collapsed.tsv"
need_collapse=1
if [[ -s "$collapsed" ]]; then
    need_collapse=0
    for sample in "${SAMPLES[@]}"; do
        vcfgz="${RESULTS}/${sample}.vcf.gz"
        if [[ "$vcfgz" -nt "$collapsed" ]]; then
            need_collapse=1
            break
        fi
    done
fi

if [[ "$need_collapse" -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            vcfgz="${RESULTS}/${sample}.vcf.gz"
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfgz"
        done
    } > "$collapsed"
fi