#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.fai" ]; then
    samtools faidx "$REF"
fi
bwa_index_files=(data/ref/chrM.fa.amb data/ref/chrM.fa.ann data/ref/chrM.fa.bwt data/ref/chrM.fa.pac data/ref/chrM.fa.sa)
if [ ! -f "${bwa_index_files[0]}" ]; then
    bwa index "$REF"
fi

# Step 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="${vcf}.gz"
    tbi="${vcf_gz}.tbi"

    # Step 3-4: Alignment and sorting (idempotent)
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ $THREADS -o "$bam" -
    fi

    # Step 5: BAM indexing (idempotent)
    if [ ! -f "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Step 6: Variant calling (idempotent)
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF" \
            --out "$vcf" \
            --sig \
            --bonf \
            "$bam"
    fi

    # Step 7: VCF compression and indexing (idempotent)
    if [ ! -f "$tbi" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Step 8: Collapse step (idempotent)
collapsed="results/collapsed.tsv"
need_rebuild=0
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_rebuild=1
        break
    fi
done

if [ "$need_rebuild" -eq 1 ] || [ ! -f "$collapsed" ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi